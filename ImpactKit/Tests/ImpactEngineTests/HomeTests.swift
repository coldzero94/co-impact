import Foundation
import ImpactEngine
import Testing

/// Los Angeles differs from both UTC (CI) and KST, so a slip to `Calendar.current` fails somewhere.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()
private let midnight = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!
private let zoom = URL(string: "https://zoom.us/j/123")!
private let clinic = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)

private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute, second: second), to: midnight)!
}

/// An online meeting by default. A custom `edit` replaces that default, so the event has no link unless `edit` sets one.
private func event(
    _ id: String, _ hour: Int, _ minute: Int = 0, day: Int = 0, minutes: Int = 60,
    _ edit: (inout CalendarEvent) -> Void = { $0.url = zoom }
) -> CalendarEvent {
    let start = at(hour, minute, day: day)
    var event = CalendarEvent(id: id, calendarID: "personal", title: id, start: start, end: start.addingTimeInterval(Double(minutes) * 60))
    edit(&event)
    return event
}

/// The UX.md mock-up's today cards, plus events with no card (room label, all-day) and one tomorrow event.
private let mockDay = [
    event("Design review", 10),
    event("Dentist", 14, 30) { $0.structuredPlace = clinic },
    event("Town hall", 17) { $0.url = zoom; $0.structuredPlace = clinic },
    event("Team sync", 11) { $0.location = "회의실 3A" },
    event("Holiday", 0) { $0.isAllDay = true },
    event("Tomorrow standup", 9, day: 1),
]

private func ids(_ cards: [ImpactCard]) -> [String] { cards.map(\.id) }

@Suite struct HomeTests {
    private let engine: ImpactEngine

    init() throws { engine = try ImpactEngine() }

    private func home(
        _ events: [CalendarEvent], at now: Date, completed: Set<String> = [], impacts: Int = 0,
        suppressionRules: [SuppressionRule] = [], includedCalendarIDs: Set<String> = []
    ) -> HomeSnapshot {
        engine.home(events: events, now: now, calendar: calendar, completedCardIDs: completed, impactsToday: impacts,
                    suppressionRules: suppressionRules, includedCalendarIDs: includedCalendarIDs)
    }

    @Test("Mock-up day: Next up, later today, summary, and ring")
    func layout() {
        let home = home(mockDay, at: at(9, 48))
        #expect(home.nextUp?.id == "Design review")
        #expect(ids(home.laterToday) == ["Dentist", "Town hall"])
        #expect(home.tomorrowMorning.isEmpty)
        #expect(home.eventsLeftToday == 4)
        #expect(home.doneCardIDs.isEmpty)
        #expect(home.ringSegments == 3)
    }

    @Test("Cards are ordered by start, then ID, whatever order events arrive in")
    func ordering() {
        let home = home(mockDay.reversed() + [event("B", 12), event("A", 12)], at: at(9, 48))
        #expect(home.nextUp?.id == "Design review")
        #expect(ids(home.laterToday) == ["A", "B", "Dentist", "Town hall"])
    }

    @Test("A done card leaves Next up but stays listed and marked done, after the cards still to do")
    func doneCard() {
        let home = home(mockDay, at: at(10, 2), completed: ["Design review"], impacts: 1)
        #expect(home.nextUp?.id == "Dentist")
        #expect(ids(home.laterToday) == ["Town hall", "Design review"])
        #expect(home.doneCardIDs == ["Design review"])
        #expect(home.impactsToday == 1)
        #expect(home.ringSegments == 3)
    }

    @Test("Next up is the earliest card in Soon or Now; Now ends 10 minutes after the start", arguments: [
        (at(10, 9, 59), "A"), (at(10, 10), "B"),
    ])
    func nowEnds(_ now: Date, _ next: String) {
        #expect(home([event("A", 10), event("B", 10, 5)], at: now).nextUp?.id == next)
    }

    @Test("Back to back: the next meeting takes over when it reaches Soon, 15 minutes before", arguments: [
        (at(10, 44, 59), "Design review", ["Team sync"]), (at(10, 45), "Team sync", ["Design review"]),
    ])
    func backToBack(_ now: Date, _ next: String, _ later: [String]) {
        let home = home([event("Design review", 10), event("Team sync", 11)], at: now)
        #expect(home.nextUp?.id == next)
        #expect(ids(home.laterToday) == later)
    }

    @Test("Without a card in Soon or Now, the latest running card leads, else the next card", arguments: [
        (at(8), "Long"), (at(10, 20), "Short"), (at(11, 30), "Long"),
    ])
    func fallback(_ now: Date, _ next: String) {
        let events = [event("Long", 9, minutes: 180), event("Short", 10), event("Town hall", 17)]
        #expect(home(events, at: now).nextUp?.id == next)
    }

    @Test("In-person Soon/Now runs from 30 minutes before the start until the start; hybrid follows the online window", arguments: [
        (at(13, 59, 59), "Call"), (at(14), "Dentist"), (at(14, 30), "Check-in"), (at(17, 5), "Town hall"),
    ])
    func soonByKind(_ now: Date, _ next: String) {
        let events = [
            event("Call", 13, 30, minutes: 120), event("Dentist", 14, 30) { $0.structuredPlace = clinic },
            event("Check-in", 14, 35), event("Town hall", 17) { $0.url = zoom; $0.structuredPlace = clinic },
            event("Wrap-up", 17, 10),
        ]
        #expect(home(events, at: now).nextUp?.id == next)
    }

    @Test("In-person cards expire 15 minutes after the start and leave the ring", arguments: [
        (at(14, 44, 59), true), (at(14, 45), false),
    ])
    func inPersonExpiry(_ now: Date, _ listed: Bool) {
        let home = home(mockDay, at: now)
        let shown = ids([home.nextUp].compactMap(\.self) + home.laterToday)
        #expect(shown.contains("Dentist") == listed)
        #expect(home.ringSegments == (listed ? 2 : 1))
    }

    @Test("Hybrid cards stay until the event ends")
    func hybridStays() {
        #expect(home(mockDay, at: at(17, 50)).nextUp?.id == "Town hall")
    }

    @Test("Tomorrow morning appears from 18:00, with the earliest two cards", arguments: [
        (at(17, 59, 59), false), (at(18), true),
    ])
    func tomorrowFromEvening(_ now: Date, _ shown: Bool) {
        let tomorrow = [event("T 07:00 declined", 7, day: 1) { $0.url = zoom; $0.participation = .declined }]
            + [(8, 30), (9, 0), (11, 30)].map { event("T \($0.0):\($0.1)", $0.0, $0.1, day: 1) }.reversed()
        let home = home([event("Late call", 19)] + tomorrow, at: now)
        #expect(home.nextUp?.id == "Late call")
        #expect(ids(home.tomorrowMorning) == (shown ? ["T 8:30", "T 9:0"] : []))
    }

    @Test("Cards lists Next up, later today, and tomorrow morning; a done card stays, an expired one leaves")
    func cards() {
        let events = mockDay + [event("Early sync", 9, 30)]
        #expect(ids(home(events, at: at(9, 48)).cards) == ["Design review", "Early sync", "Dentist", "Town hall"])
        let afterDone = home(events, at: at(10, 2), completed: ["Design review"])
        #expect(ids(afterDone.cards).contains("Design review"))
        #expect(ids(home(events, at: at(19)).cards) == ["Tomorrow standup"])
    }

    @Test("An untitled event's card reads Untitled; its Title fact keeps the calendar's empty title")
    func untitled() throws {
        let card = try #require(try ImpactEngine().card(for: event("", 10), now: at(9)))
        #expect(card.title == "Untitled" && card.facts.first { $0.label == "Title" }?.value == "")
    }

    @Test("Today ends at midnight, Tomorrow morning at noon, and the fetch at the end of the sixth day after today")
    func horizon() {
        let (tomorrow, noon, end) = ImpactEngine.horizon(now: at(19), calendar: calendar)
        #expect(tomorrow == at(0, day: 1) && noon == at(12, day: 1) && end == at(0, day: 7))
        // On 2027-03-14 clocks spring forward at 02:00 in Los Angeles, so that day is 23 hours long.
        let springForward = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 19))!
        let (dstTomorrow, dstNoon, _) = ImpactEngine.horizon(now: springForward, calendar: calendar)
        #expect(dstTomorrow == calendar.date(from: DateComponents(year: 2027, month: 3, day: 15))!)
        #expect(dstNoon == calendar.date(from: DateComponents(year: 2027, month: 3, day: 15, hour: 12))!)
        // The evening before, tomorrow is the short day: noon is 11 hours after midnight, not 12.
        let eve = calendar.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 19))!
        #expect(ImpactEngine.horizon(now: eve, calendar: calendar).noon
                == calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 12))!)
        // The week ahead spans the change: it ends at midnight, not at 23:00 or 01:00.
        #expect(ImpactEngine.horizon(now: eve, calendar: calendar).end
                == calendar.date(from: DateComponents(year: 2027, month: 3, day: 20))!)
        // Where DST starts at midnight (Beirut, 2026-03-29), tomorrow starts at 01:00; the fetch still ends at
        // midnight, so it never reaches today's weekday.
        var beirut = Calendar(identifier: .gregorian)
        beirut.timeZone = TimeZone(identifier: "Asia/Beirut")!
        let saturday = beirut.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 19))!
        #expect(ImpactEngine.horizon(now: saturday, calendar: beirut).end
                == beirut.date(from: DateComponents(year: 2026, month: 4, day: 4))!)
    }

    @Test("With nothing listed left to do, the next card not done after them; none past the fetched week")
    func next() {
        let events = [
            event("Today", 10),
            event("Tomorrow", 9, day: 1),
            event("Room only", 10, day: 2) { $0.location = "회의실 3A" },
            event("Dismissed", 11, day: 2),
            event("Done early", 12, day: 2),
            event("Planning", 13, day: 2),
        ]
        #expect(home(events, at: at(9)).next == nil)
        // Today's card is done but still listed, so Tomorrow morning is hidden and its card comes next.
        #expect(home(events, at: at(10, 5), completed: ["Today"]).next?.id == "Tomorrow")
        // From 18:00 tomorrow's card is listed: while it is to do there is no next.
        #expect(home(events, at: at(19), completed: ["Today"]).next == nil)
        let rest = home(events, at: at(19), completed: ["Today", "Tomorrow", "Done early"],
                        suppressionRules: [.occurrence(id: "Dismissed")])
        #expect(rest.next?.id == "Planning" && !ids(rest.cards).contains("Planning"))
        // Nothing listed at all, the usual empty day: the week's first card, whatever order events arrive in.
        #expect(home([event("Later", 9, day: 4), event("Sooner", 9, day: 2)], at: at(15)).next?.id == "Sooner")
        // A third tomorrow-morning card is not listed, so it is next once the two listed ones are done.
        let mornings = [event("M1", 8, day: 1), event("M2", 9, day: 1), event("M3", 10, day: 1), event("Later", 9, day: 3)]
        #expect(home(mornings, at: at(19), completed: ["M1", "M2"]).next?.id == "M3")
        // The fetched week ends at midnight: an event starting then is past it, one a minute earlier is not.
        #expect(home([event("Day 7", 0, day: 7)], at: at(19)).next == nil)
        #expect(home([event("Day 6", 23, 59, day: 6)], at: at(19)).next?.id == "Day 6")
    }

    @Test("Now runs from 10 minutes before an online start to 10 after it, and in person until the start")
    func nowPhase() throws {
        let online = try #require(engine.card(for: event("Online", 10), now: at(9)))
        let visit = try #require(engine.card(for: event("Visit", 10) { $0.structuredPlace = clinic }, now: at(9)))
        #expect(ImpactEngine.nowPhase(of: online) == at(9, 50) ..< at(10, 10))
        #expect(ImpactEngine.nowPhase(of: visit) == at(9, 50) ..< at(10))
    }

    @Test("Live Activities go to the next two cards still to do whose Now has not ended, by Now start")
    func liveActivityCards() {
        let events = [
            event("Done", 9, 30), event("Running", 9), event("Visit", 10) { $0.structuredPlace = clinic },
            event("Review", 10, 5), event("Later", 14),
        ]
        let home = home(events, at: at(9, 15), completed: ["Done"])
        // Running's Now (8:50–9:10) has ended; Done is done; Visit's Now starts 9:50, Review's 9:55.
        #expect(ids(ImpactEngine.liveActivityCards(in: home, now: at(9, 15))) == ["Visit", "Review"])
        // Inside Visit's Now it still counts; once it ends, Later moves up.
        #expect(ids(ImpactEngine.liveActivityCards(in: home, now: at(9, 55))) == ["Visit", "Review"])
        #expect(ids(ImpactEngine.liveActivityCards(in: home, now: at(10))) == ["Review", "Later"])
    }

    @Test("Tomorrow morning ends before noon")
    func tomorrowNoon() {
        let events = [event("Midnight", 0, day: 1), event("Noon", 12, day: 1), event("After noon", 13, day: 1)]
        let home = home(events, at: at(18))
        #expect(ids(home.tomorrowMorning) == ["Midnight"])
        #expect(home.nextUp == nil)
    }

    @Test("Tomorrow morning appears once today has no cards listed; a done card still listed keeps it hidden", arguments: [
        (13, true), (16, false),
    ])
    func tomorrowWhenNoCardsListed(_ hour: Int, _ shown: Bool) {
        let events = [event("Last meeting", hour), event("Client visit", 8, 30, day: 1) { $0.structuredPlace = clinic }]
        let home = home(events, at: at(15), completed: ["Last meeting", "Client visit"], impacts: 2)
        #expect(home.nextUp == nil)
        #expect(ids(home.tomorrowMorning) == (shown ? ["Client visit"] : []))
        #expect(home.doneCardIDs == (shown ? ["Client visit"] : ["Last meeting"]))
    }

    @Test("A card done before midnight stays done after it")
    func doneBeforeMidnight() {
        // Directions to a 00:30 visit counts from 22:30 the day before (ActionLog.countsFrom).
        let home = home([event("Client visit", 0, 30) { $0.structuredPlace = clinic }], at: at(0, 10), completed: ["Client visit"])
        #expect(home.nextUp == nil)
        #expect(ids(home.laterToday) == ["Client visit"])
        #expect(home.doneCardIDs == ["Client visit"])
        #expect(home.impactsToday == 0)
        #expect(home.ringSegments == 0)
    }

    @Test("The summary counts the user's own valid timed events that have not ended, including running ones")
    func eventCount() {
        let events = mockDay + [
            event("Running", 9, minutes: 120) { _ in },
            event("Ended", 8) { _ in },
            event("Empty", 15, minutes: 0) { _ in },
            event("Canceled", 12) { $0.isCanceled = true },
            event("Declined", 13) { $0.participation = .declined },
            event("Someone else's", 15) { $0.hasAttendees = true },
            event("Subscribed", 16) { $0.calendarKind = .subscription },
        ]
        #expect(home(events, at: at(9, 48)).eventsLeftToday == 5)
    }

    @Test("Muted events leave Home but still count; opted-in calendars count and show")
    func userFeedback() {
        let shared = event("Shared", 12) { $0.url = zoom; $0.calendarID = "team"; $0.calendarKind = .subscription }
        let events = mockDay + [shared]
        let muted = SuppressionRule.title(calendarID: "personal", title: "Town hall")
        let home = home(events, at: at(9, 48), suppressionRules: [muted], includedCalendarIDs: ["team"])
        #expect(ids(home.laterToday) == ["Shared", "Dentist"])
        #expect(home.eventsLeftToday == 5)
        #expect(self.home(events, at: at(9, 48)).eventsLeftToday == 4)
    }
}

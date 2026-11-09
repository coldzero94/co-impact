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

    @Test("A done card leaves Next up but stays listed and marked done")
    func doneCard() {
        let home = home(mockDay, at: at(10, 2), completed: ["Design review"], impacts: 1)
        #expect(home.nextUp?.id == "Dentist")
        #expect(ids(home.laterToday) == ["Design review", "Town hall"])
        #expect(home.doneCardIDs == ["Design review"])
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

    @Test("A card done the evening before stays done the next morning")
    func doneTheEveningBefore() {
        let home = home([event("Client visit", 8, 30) { $0.structuredPlace = clinic }], at: at(7, 30), completed: ["Client visit"])
        #expect(home.nextUp == nil)
        #expect(ids(home.laterToday) == ["Client visit"])
        #expect(home.doneCardIDs == ["Client visit"])
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

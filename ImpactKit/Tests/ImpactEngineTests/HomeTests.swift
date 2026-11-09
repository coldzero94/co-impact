import Foundation
import ImpactEngine
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
/// Midnight UTC, so hours below read as clock times.
private let midnight = Date(timeIntervalSince1970: 1_799_971_200)
private let zoom = URL(string: "https://zoom.us/j/123")!
private let clinic = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)

private func at(_ hour: Double, day: Int = 0) -> Date {
    midnight.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
}

private func event(_ id: String, _ hour: Double, day: Int = 0, _ edit: (inout CalendarEvent) -> Void = { $0.url = zoom }) -> CalendarEvent {
    var event = CalendarEvent(id: id, calendarID: "personal", title: id, start: at(hour, day: day), end: at(hour + 1, day: day))
    edit(&event)
    return event
}

private let morning = [
    event("Design review", 10),
    event("Dentist", 14.5) { $0.structuredPlace = clinic },
    event("Town hall", 17),
    event("Team sync", 11) { $0.location = "회의실 3A" },
    event("Holiday", 0) { $0.isAllDay = true },
    event("Tomorrow standup", 9, day: 1),
]

@Suite struct HomeTests {
    private let engine: ImpactEngine

    init() throws { engine = try ImpactEngine() }

    private func home(_ events: [CalendarEvent], at hour: Double, completed: Set<String> = []) -> HomeSnapshot {
        engine.home(events: events, now: at(hour), calendar: utc, completedToday: completed)
    }

    @Test("The earliest card is Next up; the rest are later today")
    func layout() {
        let home = home(morning, at: 9.8)
        #expect(home.nextUp?.id == "Design review")
        #expect(home.laterToday.map(\.id) == ["Dentist", "Town hall"])
        #expect(home.tomorrowMorning.isEmpty)
        #expect(home.eventsLeftToday == 4)
        #expect(home.impactsToday == 0)
        #expect(home.ringSegments == 3)
    }

    @Test("A done card leaves Next up but stays listed, and fills a ring segment")
    func doneCard() {
        let home = home(morning, at: 10.2, completed: ["Design review"])
        #expect(home.nextUp?.id == "Dentist")
        #expect(home.laterToday.map(\.id) == ["Design review", "Town hall"])
        #expect(home.impactsToday == 1)
        #expect(home.ringSegments == 3)
    }

    @Test("In-person cards expire 15 minutes after the start and leave the ring", arguments: [(14.74, true), (14.75, false)])
    func inPersonExpiry(_ hour: Double, _ listed: Bool) {
        let home = home(morning, at: hour)
        let ids = ([home.nextUp].compactMap(\.self) + home.laterToday).map(\.id)
        #expect(ids.contains("Dentist") == listed)
        #expect(home.ringSegments == (listed ? 2 : 1))
    }

    @Test("Tomorrow morning appears from 18:00, with at most two cards before noon", arguments: [(17.99, false), (18.0, true)])
    func tomorrowFromEvening(_ hour: Double, _ shown: Bool) {
        let events = [event("Late call", 19)] + [8.5, 9, 11.5, 13].map { event("Tomorrow \($0)", $0, day: 1) }
        let home = home(events, at: hour)
        #expect(home.nextUp?.id == "Late call")
        #expect(home.tomorrowMorning.map(\.id) == (shown ? ["Tomorrow 8.5", "Tomorrow 9.0"] : []))
    }

    @Test("Tomorrow morning appears once nothing is left to do today")
    func tomorrowWhenDone() {
        let events = [event("Last meeting", 16), event("Client visit", 8.5, day: 1) { $0.structuredPlace = clinic }]
        let home = home(events, at: 15, completed: ["Last meeting"])
        #expect(home.nextUp == nil)
        #expect(home.laterToday.map(\.id) == ["Last meeting"])
        #expect(home.tomorrowMorning.map(\.id) == ["Client visit"])
    }

    @Test("The summary counts only the user's own timed events that have not ended")
    func eventCount() {
        let events = morning + [
            event("Ended", 8),
            event("Canceled", 12) { $0.isCanceled = true },
            event("Declined", 13) { $0.participation = .declined },
            event("Someone else's", 15) { $0.hasAttendees = true },
            event("Subscribed", 16) { $0.calendarKind = .subscription },
        ]
        #expect(home(events, at: 9.8).eventsLeftToday == 4)
    }
}

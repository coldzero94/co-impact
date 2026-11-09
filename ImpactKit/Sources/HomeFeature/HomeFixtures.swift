import Foundation
import ImpactEngine

#if DEBUG
/// Synthetic events for previews and debug builds; never real calendar data (AGENTS.md hard rule 7).
public enum HomeFixtures {
    /// A sample day seen at `hour` (09:48 by default: two Impacts made, three cards to go).
    @MainActor
    public static func sample(at hour: Double = 9.8, calendar: Calendar = .current, today: Date = .now) throws -> HomeModel {
        let day = calendar.startOfDay(for: today)
        // shortcut: fixed offsets from midnight shift by an hour on DST change days; fine for samples.
        func at(_ hour: Double, day offset: Int = 0) -> Date {
            day.addingTimeInterval(Double(offset) * 86_400 + hour * 3_600)
        }
        func event(_ title: String, _ hour: Double, minutes: Double = 60, day offset: Int = 0,
                   _ edit: (inout CalendarEvent) -> Void) -> CalendarEvent {
            var event = CalendarEvent(id: title, calendarID: "work", title: title,
                                      start: at(hour, day: offset), end: at(hour + minutes / 60, day: offset))
            edit(&event)
            return event
        }
        let clinic = Place(title: "Seongsu Dental", address: "12 Synthetic-ro, Seongdong-gu", latitude: 37.544, longitude: 127.056)
        let hall = Place(title: "City Hall", address: "110 Sejong-daero", latitude: 37.566, longitude: 126.978)
        let events = [
            event("Standup", 7.5, minutes: 45) { $0.url = URL(string: "https://zoom.us/j/111") },
            event("1:1 with Mina", 9, minutes: 30) { $0.location = "https://meet.google.com/abc-defg-hij" },
            event("Design review", 10) { $0.notes = "Join https://zoom.us/j/123456" },
            event("Team sync", 11, minutes: 30) { $0.location = "회의실 3A" },
            event("Dentist", 14.5) { $0.structuredPlace = clinic },
            event("Town hall", 17) {
                $0.location = "110 Sejong-daero"; $0.geocodedPlace = hall
                $0.notes = "https://teams.microsoft.com/l/meetup-join/synthetic"
            },
            event("Client visit", 8.5, day: 1) { $0.structuredPlace = hall },
        ]
        // Joined at their start: Standup by 08:00, and 1:1 with Mina too by 09:30.
        let engine = try ImpactEngine()
        var log = ActionLog()
        for event in events.prefix(hour >= 9.5 ? 2 : 1) {
            guard let card = engine.card(for: event, now: event.start) else { preconditionFailure("\(event.title) has no card") }
            log.record(card.actions[0], on: card, at: event.start)
        }
        return try HomeModel(events: events, now: at(hour), calendar: calendar, log: log)
    }
}
#endif

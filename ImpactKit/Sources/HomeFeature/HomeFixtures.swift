import Foundation
import ImpactEngine

/// Synthetic events for previews and debug builds; never real calendar data (AGENTS.md hard rule 7).
public struct HomeFixture: Sendable {
    public let snapshot: HomeSnapshot
    public let now: Date
    public let impactsToday: Int
}

public enum HomeFixtures {
    /// Today at 09:48: one Impact already made, three cards to go.
    public static func morning(calendar: Calendar = .current, now: Date = .now) throws -> HomeFixture {
        let day = calendar.startOfDay(for: now)
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
        let now = at(9.8)
        let snapshot = try ImpactEngine().home(
            events: events, now: now, calendar: calendar, completedCardIDs: ["1:1 with Mina"], impactsToday: 1)
        return HomeFixture(snapshot: snapshot, now: now, impactsToday: 1)
    }
}

import Foundation
import ImpactEngine

#if DEBUG
enum FixtureError: LocalizedError {
    case noCard(String)

    var errorDescription: String? {
        switch self { case .noCard(let title): "Sample event \"\(title)\" produced no card" }
    }
}

/// Synthetic events for previews and debug builds; never real calendar data (AGENTS.md hard rule 7).
public enum HomeFixtures {
    /// A sample day seen at `hour` (09:48 by default: two Impacts made, four cards to go), with one goal whose session
    /// is blocked at 15:30, a focus block; from 15:45 until it ends, a focus session runs on it since 15:30.
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
            event("Design review", 10) {
                $0.notes = "Agenda: onboarding flow, then open questions.\nJoin https://zoom.us/j/123456"
                $0.hasAttendees = true; $0.isUserAttendee = true; $0.participation = .accepted
                $0.organizer = "Mina Park"
                $0.attendees = ["Joon Lee", "Sara Kim", "Alex Cho", "Dana Yoon", "Eli Han"]
            },
            event("Team sync", 11, minutes: 30) { $0.location = "회의실 3A" },
            event("Dentist", 14.5) { $0.structuredPlace = clinic },
            event("Write a book", 15.5) { _ in },
            event("Town hall", 17) {
                $0.location = "110 Sejong-daero"; $0.geocodedPlace = hall
                $0.notes = "https://teams.microsoft.com/l/meetup-join/synthetic"
                $0.hasAttendees = true; $0.isUserAttendee = true; $0.organizer = "Events team"
            },
            event("Client visit", 8.5, day: 1) { $0.structuredPlace = hall },
            event("Quarterly planning", 10, day: 2) { $0.url = URL(string: "https://zoom.us/j/222") },
        ]
        // Joined at their start: Standup always, and 1:1 with Mina too from 09:30. From 20:00, tomorrow's Client
        // visit is dismissed as not needed, so the empty state names the next card.
        let engine = try ImpactEngine()
        var log = ActionLog()
        for event in events.prefix(hour >= 9.5 ? 2 : 1) {
            guard let card = engine.card(for: event, now: event.start), let primary = card.primaryAction else {
                throw FixtureError.noCard(event.title)
            }
            log.record(primary, on: card, at: event.start)
        }
        var dismissals = Dismissals()
        if hour >= 20 { dismissals.dismiss(events[7], at: at(20)) }
        // Met for the week, so no goal-time card joins the sample day.
        let goals = GoalSettings(goals: [Goal(id: "book", title: "Write a book", timesPerWeek: 1)], offered: true)
        let records = GoalRecords(sessions: [GoalSession(goalID: "book", eventID: "Write a book", title: "Write a book",
                                                         start: at(15.5), end: at(16.5))])
        // Block time keeps its events in memory: fixtures never write to the calendar.
        let blocks = BlockWriter(add: { title, slot in
            CalendarEvent(id: UUID().uuidString, calendarID: "work", title: title, start: slot.start, end: slot.end)
        }, remove: { _ in })
        var block = events[5]
        block.focusGoal = "Write a book"
        let focus = (15.75..<16.5).contains(hour) ? engine.card(for: block, now: at(15.5)).flatMap { FocusSession(card: $0, now: at(15.5)) } : nil
        return try HomeModel(events: events, now: at(hour), calendar: calendar, log: log, dismissals: dismissals,
                             goals: goals, goalRecords: records, blocks: blocks, focus: focus)
    }
}
#endif

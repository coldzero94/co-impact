import Foundation

/// An event Impact created with Block time (PRODUCT.md → Block time), as last seen in the calendar.
public struct GoalSession: Sendable, Hashable, Codable {
    public let goalID: String
    /// The event's `CalendarEvent.id`; it can change after a sync, as can its calendar's ID, so `GoalRecords.matched`
    /// falls back to the title and start.
    public var eventID: String
    public var title: String
    public var start: Date
    public var end: Date

    public init(goalID: String, eventID: String, title: String, start: Date, end: Date) {
        self.goalID = goalID
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
    }
}

/// What goal-time cards remember: the sessions Impact blocked, and the user's answers today.
/// Stored as its synthesized `Codable` (and `GoalSession`'s and `GoalAnswer`'s): renaming a property, or adding a
/// non-optional one, sets stored records aside; `LiveDataTests.goalRecordsStore` pins the format.
public struct GoalRecords: Sendable, Hashable, Codable {
    public private(set) var sessions: [GoalSession] = []
    public private(set) var answers: [GoalAnswer] = []

    public init(sessions: [GoalSession] = [], answers: [GoalAnswer] = []) {
        self.sessions = sessions
        self.answers = answers
    }

    /// Block time: records the event Impact created and the answer.
    public mutating func block(_ session: GoalSession, at date: Date) {
        sessions.append(session)
        answers.append(GoalAnswer(goalID: session.goalID, date: date, blocked: true))
    }

    /// Undo after Block time: the event is gone, and so is the answer it gave. A session already undone changes nothing.
    public mutating func undo(_ session: GoalSession) {
        let count = sessions.count
        sessions.removeAll { $0.eventID == session.eventID }
        guard sessions.count < count,
              let last = answers.lastIndex(where: { $0.goalID == session.goalID && $0.blocked }) else { return }
        answers.remove(at: last)
    }

    /// Not now: hides the goal's card until tomorrow.
    public mutating func notNow(_ goal: Goal, at date: Date) {
        answers.append(GoalAnswer(goalID: goal.id, date: date, blocked: false))
    }

    /// The records as the calendar has them now. `events` is Home's fetch, from the start of today: a session found
    /// there by its event ID, or else by title and start (a full sync can change both the event's and its calendar's ID,
    /// ARCHITECTURE.md → Platform facts), takes the event's ID, title, and times, so moving it in Calendar
    /// moves the block; one from today on that is not found was deleted (or moved out of reach) and is dropped. A
    /// fallback match only counts the event as a session; nothing is ever written to it. Sessions before today are kept as last seen,
    /// until their week is over; answers only for today.
    /// shortcut: the fallback needs the start unchanged since Impact last saw it; check how Google and Exchange keep
    /// IDs on a device (ARCHITECTURE.md → To verify) before relying on more.
    public func matched(events: [CalendarEvent], now: Date, calendar: Calendar) -> GoalRecords {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var taken: Set<String> = []
        let kept = sessions.compactMap { session -> GoalSession? in
            guard session.start >= today else { return session.start >= weekStart ? session : nil }
            let found = byID[session.eventID].flatMap { taken.contains($0.id) ? nil : $0 }
                ?? events.first {
                    !taken.contains($0.id) && $0.title == session.title && $0.start == session.start && !$0.isCanceled
                }
            guard let event = found, !event.isCanceled else { return nil }
            taken.insert(event.id)
            var seen = session
            seen.eventID = event.id
            seen.title = event.title
            seen.start = event.start
            seen.end = event.end
            return seen
        }
        return GoalRecords(sessions: kept, answers: answers.filter { calendar.isDate($0.date, inSameDayAs: now) })
    }

    /// `ImpactEngine.goalTimeCard(sessions:)`: the sessions by goal ID.
    public var sessionsByGoal: [String: [DateInterval]] {
        Dictionary(grouping: sessions, by: \.goalID).mapValues { $0.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) } }
    }
}

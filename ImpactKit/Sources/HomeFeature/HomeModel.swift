import Foundation
import ImpactEngine
import Observation

/// Home's state: the fetched events, the clock, and the action log, with the snapshot built from them.
@Observable @MainActor
public final class HomeModel {
    public private(set) var snapshot: HomeSnapshot
    /// shortcut: fixed, so countdowns and phases do not move; rebuild `now` and the snapshot together on a
    /// schedule once live data arrives (roadmap step 7).
    public let now: Date
    private(set) var log: ActionLog
    private let events: [CalendarEvent]
    private let calendar: Calendar
    private let engine: ImpactEngine

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog()) throws {
        let engine = try ImpactEngine()
        snapshot = Self.home(engine, events, now, calendar, log)
        self.now = now
        self.log = log
        self.events = events
        self.calendar = calendar
        self.engine = engine
    }

    /// Records an action the system opened (PRODUCT.md → Completion semantics); true when it recorded an Impact.
    func record(_ action: ImpactAction, on card: ImpactCard) -> Bool {
        let recorded = log.record(action, on: card, at: now)
        snapshot = Self.home(engine, events, now, calendar, log)
        return recorded
    }

    private static func home(
        _ engine: ImpactEngine, _ events: [CalendarEvent], _ now: Date, _ calendar: Calendar, _ log: ActionLog
    ) -> HomeSnapshot {
        engine.home(events: events, now: now, calendar: calendar, completedCardIDs: log.completedCardIDs,
                    impactsToday: log.impactCount(on: now, calendar: calendar))
    }
}

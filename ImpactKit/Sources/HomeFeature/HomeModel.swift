import Foundation
import ImpactEngine
import Observation

/// Home's state: the fetched events, the clock, and the action log, with the snapshot built from them.
@Observable @MainActor
public final class HomeModel {
    public private(set) var snapshot: HomeSnapshot
    /// The time the snapshot was built for; `update` moves it (live Home does every minute). `record` stamps
    /// Impacts with it, so a stamp can be up to a minute early.
    public private(set) var now: Date
    private(set) var log: ActionLog
    private var events: [CalendarEvent]
    private let calendar: Calendar
    private let engine: ImpactEngine
    /// Receives every recorded Impact after a new one, to store them.
    private let saveImpacts: ([String: Date]) -> Void

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog(),
                saveImpacts: @escaping ([String: Date]) -> Void = { _ in }) throws {
        let engine = try ImpactEngine()
        snapshot = Self.home(engine, events, now, calendar, log)
        self.now = now
        self.log = log
        self.events = events
        self.calendar = calendar
        self.engine = engine
        self.saveImpacts = saveImpacts
    }

    /// Rebuilds the snapshot for newly fetched events at a new time.
    public func update(events: [CalendarEvent], now: Date) {
        self.events = events
        self.now = now
        snapshot = Self.home(engine, events, now, calendar, log)
    }

    /// Adds Impacts read from storage after launch (it was unreadable then), and stores the union.
    func restore(_ stored: [String: Date]) {
        log.restore(stored)
        snapshot = Self.home(engine, events, now, calendar, log)
        saveImpacts(log.impacts)
    }

    /// Records an action the system accepted (PRODUCT.md → Completion semantics); true when it recorded an Impact.
    func record(_ action: ImpactAction, on card: ImpactCard) -> Bool {
        let recorded = log.record(action, on: card, at: now)
        snapshot = Self.home(engine, events, now, calendar, log)
        if recorded { saveImpacts(log.impacts) }
        return recorded
    }

    private static func home(
        _ engine: ImpactEngine, _ events: [CalendarEvent], _ now: Date, _ calendar: Calendar, _ log: ActionLog
    ) -> HomeSnapshot {
        engine.home(events: events, now: now, calendar: calendar, completedCardIDs: log.completedCardIDs,
                    impactsToday: log.impactCount(on: now, calendar: calendar))
    }
}

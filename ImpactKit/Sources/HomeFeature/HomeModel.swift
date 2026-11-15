import Foundation
import ImpactEngine
import Observation

/// Home's state: the fetched events, the clock, the action log, and dismissals, with the snapshot built from them.
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
    private var dismissals: Dismissals
    /// Receives every Impact after one is recorded or restored, to store them.
    private let saveImpacts: ([String: Date]) -> Void
    /// Receives the dismissals after each change, to store them.
    private let saveDismissals: (Dismissals) -> Void

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog(),
                dismissals: Dismissals = Dismissals(),
                saveImpacts: @escaping ([String: Date]) -> Void = { _ in },
                saveDismissals: @escaping (Dismissals) -> Void = { _ in }) throws {
        let engine = try ImpactEngine()
        snapshot = Self.home(engine, events, now, calendar, log, dismissals)
        self.now = now
        self.log = log
        self.events = events
        self.calendar = calendar
        self.engine = engine
        self.dismissals = dismissals
        self.saveImpacts = saveImpacts
        self.saveDismissals = saveDismissals
    }

    /// Rebuilds the snapshot for newly fetched events at a new time.
    public func update(events: [CalendarEvent], now: Date) {
        self.events = events
        self.now = now
        rebuild()
    }

    /// Adds Impacts read from storage after launch (it was unreadable then), and stores the union.
    func restore(_ stored: [String: Date]) {
        log.restore(stored)
        rebuild()
        saveImpacts(log.impacts)
    }

    /// "Not needed" hides this card's occurrence; with `similar`, "Don't suggest for events like this" mutes its
    /// series or title too (UX.md → Dismissing). The card leaves Home at once and its ring segment with it.
    func dismiss(_ card: ImpactCard, similar: Bool) {
        guard let event = events.first(where: { $0.id == card.id }) else { return }
        if similar {
            dismissals.mute(like: event)
        } else {
            dismissals.dismiss(event)
        }
        rebuild()
        saveDismissals(dismissals)
    }

    /// Records an action the system accepted (PRODUCT.md → Completion semantics); true when it recorded an Impact.
    func record(_ action: ImpactAction, on card: ImpactCard) -> Bool {
        let recorded = log.record(action, on: card, at: now)
        rebuild()
        if recorded { saveImpacts(log.impacts) }
        return recorded
    }

    private func rebuild() {
        snapshot = Self.home(engine, events, now, calendar, log, dismissals)
    }

    private static func home(
        _ engine: ImpactEngine, _ events: [CalendarEvent], _ now: Date, _ calendar: Calendar, _ log: ActionLog,
        _ dismissals: Dismissals
    ) -> HomeSnapshot {
        engine.home(events: events, now: now, calendar: calendar, completedCardIDs: log.completedCardIDs,
                    impactsToday: log.impactCount(on: now, calendar: calendar), suppressionRules: dismissals.rules)
    }
}

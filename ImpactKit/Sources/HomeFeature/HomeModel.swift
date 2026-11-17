import Foundation
import ImpactEngine
import LiveSurfaces
import Observation
import os

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
    /// Receives the dismissals after each dismissal, to store them.
    private let saveDismissals: (Dismissals) -> Void

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog(),
                dismissals: Dismissals = Dismissals(),
                saveImpacts: @escaping ([String: Date]) -> Void = { _ in },
                saveDismissals: @escaping (Dismissals) -> Void = { _ in }) throws {
        let engine = try ImpactEngine()
        snapshot = Self.home(engine, events, now, calendar, log, dismissals.pruned(now: now))
        self.now = now
        self.log = log
        self.events = events
        self.calendar = calendar
        self.engine = engine
        self.dismissals = dismissals.pruned(now: now)
        self.saveImpacts = saveImpacts
        self.saveDismissals = saveDismissals
    }

    /// Rebuilds the snapshot for newly fetched events at a new time.
    public func update(events: [CalendarEvent], now: Date) {
        self.events = events
        self.now = now
        // Lapse dismissals as loading does, so the result never depends on whether the app was relaunched.
        dismissals = dismissals.pruned(now: now)
        rebuild()
    }

    /// Adds Impacts read from storage after launch (it was unreadable then), and stores the union.
    func restore(_ stored: [String: Date]) {
        log.restore(stored)
        rebuild()
        saveImpacts(log.impacts)
    }

    /// "Not needed" hides this card's occurrence; with `similar`, "Don't suggest for events like this" mutes its
    /// series or title instead, which hides this occurrence as well (UX.md → Dismissing). The card leaves Home at
    /// once; a card still to do today takes its ring segment with it, while a done card's Impact still counts.
    func dismiss(_ card: ImpactCard, similar: Bool) {
        guard let event = events.first(where: { $0.id == card.id }) else {
            // A swipe on a card from before a refresh that dropped its event: nothing left to hide.
            homeLog.error("Dismissed card \(card.id, privacy: .private) (similar: \(similar, privacy: .public)) has no event in the current fetch: it is gone, or now has another ID")
            return
        }
        if similar {
            dismissals.mute(like: event, at: now)
        } else {
            dismissals.dismiss(event, at: now)
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

    /// What the widgets need to show cards as Home does (`SurfaceState`): the Impacts of the last two days or of
    /// cards still on Home (e.g. a multi-day event joined on its first day), the dismissals' rules, and the run
    /// links' secret.
    func surfaceState(runToken: String) -> SurfaceState {
        let since = now.addingTimeInterval(-2 * 86_400)
        let onHome = Set((snapshot.cards + snapshot.liveActivityCards).map(\.id))
        return SurfaceState(completed: log.impacts.filter { $0.value > since || onHome.contains($0.key) },
                            suppressionRules: dismissals.rules, runToken: runToken)
    }

    /// The card a run request names: one Home lists. The widgets, the control, and the App Shortcuts offer only
    /// today's cards and, just after midnight, one in its Soon or Now phase; a Live Activity's button, from its Now
    /// phase on. Either way Home lists the card by then (tomorrow morning's from 18:00).
    func runnableCard(id: String) -> ImpactCard? {
        snapshot.cards.first { $0.id == id }
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

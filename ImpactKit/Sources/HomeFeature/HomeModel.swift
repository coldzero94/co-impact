import Foundation
import ImpactEngine
import LiveSurfaces
import Observation
import os

/// Home's state: the fetched events, the clock, the action log, dismissals, and goals, with the snapshot built from them.
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
    /// Goals and working hours (PRODUCT.md → Goals), edited in goal setup.
    public private(set) var goals: GoalSettings
    /// The goal-time card Home shows below the time-bound cards, if any (PRODUCT.md → Goal-time rules v1).
    public private(set) var goalCard: GoalTimeCard?
    private var goalRecords: GoalRecords
    private let blocks: BlockWriter
    /// Receives every Impact after one is recorded or restored, to store them.
    private let saveImpacts: ([String: Date]) -> Void
    /// Receives the dismissals after each dismissal, to store them.
    private let saveDismissals: (Dismissals) -> Void
    /// Receives the goal settings after each change, to store them.
    private let saveGoals: (GoalSettings) -> Void
    /// Receives the goal records whenever they change, to store them.
    private let saveGoalRecords: (GoalRecords) -> Void

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog(),
                dismissals: Dismissals = Dismissals(), goals: GoalSettings = GoalSettings(),
                goalRecords: GoalRecords = GoalRecords(), blocks: BlockWriter = .unavailable,
                saveImpacts: @escaping ([String: Date]) -> Void = { _ in },
                saveDismissals: @escaping (Dismissals) -> Void = { _ in },
                saveGoals: @escaping (GoalSettings) -> Void = { _ in },
                saveGoalRecords: @escaping (GoalRecords) -> Void = { _ in }) throws {
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
        self.goals = goals
        self.saveGoals = saveGoals
        self.goalRecords = goalRecords
        self.blocks = blocks
        self.saveGoalRecords = saveGoalRecords
        rebuildGoalCard()
    }

    /// Rebuilds the snapshot for newly fetched events at a new time.
    public func update(events: [CalendarEvent], now: Date) {
        self.events = events
        self.now = now
        // Lapse dismissals as init does, so the result never depends on whether the app was relaunched.
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

    /// UX.md → Onboarding: after the first Impact, Home offers goal setup once, until it is opened or swiped away.
    public var offersGoalSetup: Bool {
        !log.impacts.isEmpty && goals.goals.isEmpty && !goals.offered
    }

    /// The offer was opened or swiped away: Home stops showing it.
    func goalSetupOffered() {
        guard !goals.offered else { return }
        goals.offered = true
        saveGoals(goals)
    }

    /// Whether goal setup's Done can save these rows: one has a title, or goals were set before (so the last one can
    /// be removed).
    func canSaveGoals(_ goals: [Goal]) -> Bool {
        !self.goals.goals.isEmpty || !Self.titled(goals).isEmpty
    }

    /// Done in goal setup: keeps the goals with a title, trimmed, at most three; none left removes them all.
    func setGoals(_ goals: [Goal], workingHours: WorkingHours) {
        self.goals = GoalSettings(goals: Array(Self.titled(goals).prefix(3)), workingHours: workingHours, offered: true)
        saveGoals(self.goals)
        rebuildGoalCard()
    }

    /// Block time (PRODUCT.md → Block time): saves the card's slot as an event and records it; the next goal-time card
    /// follows at once. Returns the session for Undo. Throws when the calendar refuses; nothing is recorded then.
    func blockTime(_ card: GoalTimeCard) throws -> GoalSession {
        let event = try blocks.add(card.goal.title, card.slot)
        let session = GoalSession(goalID: card.goal.id, eventID: event.id, calendarID: event.calendarID,
                                  title: event.title, start: event.start, end: event.end)
        // Busy at once, before the calendar's change notice brings the next fetch.
        events.append(event)
        goalRecords.block(session, at: now)
        rebuild(savingGoalRecords: true)
        return session
    }

    /// Undo within 5 seconds of Block time: removes the event Impact created, and its answer.
    func undoBlock(_ session: GoalSession) throws {
        try blocks.remove(session.eventID)
        events.removeAll { $0.id == session.eventID }
        goalRecords.undo(session)
        rebuild(savingGoalRecords: true)
    }

    /// Not now: hides this goal's card until tomorrow.
    func notNow(_ goal: Goal) {
        goalRecords.notNow(goal, at: now)
        rebuild(savingGoalRecords: true)
    }

    /// What the widgets and background refresh need to see cards as Home does (`SurfaceState`): the Impacts of the
    /// last two days or of events still fetched (e.g. a multi-day event joined on its first day, or a meeting joined
    /// and then moved), the dismissals' rules, and the run links' secret.
    func surfaceState(runToken: String) -> SurfaceState {
        let since = now.addingTimeInterval(-2 * 86_400)
        let fetched = Set(events.map(\.id))
        return SurfaceState(completed: log.impacts.filter { $0.value > since || fetched.contains($0.key) },
                            suppressionRules: dismissals.rules, runToken: runToken)
    }

    /// The card a run request names: one Home lists. The widgets, the control, and the App Shortcuts offer only
    /// today's cards and, just before midnight, one of tomorrow in its Now phase; a Live Activity's button, from its
    /// Now phase on. Either way Home lists the card by then (tomorrow morning's from 18:00).
    func runnableCard(id: String) -> ImpactCard? {
        snapshot.cards.first { $0.id == id }
    }

    private static func titled(_ goals: [Goal]) -> [Goal] {
        goals.compactMap { goal in
            var goal = goal
            goal.title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return goal.title.isEmpty ? nil : goal
        }
    }

    /// `savingGoalRecords`: the caller changed the goal records, so they are stored even if matching leaves them as is.
    private func rebuild(savingGoalRecords: Bool = false) {
        snapshot = Self.home(engine, events, now, calendar, log, dismissals)
        rebuildGoalCard(saving: savingGoalRecords)
    }

    /// Matches the blocked sessions to the calendar, stores them if that (or the caller) changed them, and picks the
    /// goal-time card.
    private func rebuildGoalCard(saving: Bool = false) {
        let matched = goalRecords.matched(events: events, now: now, calendar: calendar)
        if saving || matched != goalRecords {
            goalRecords = matched
            saveGoalRecords(matched)
        }
        goalCard = ImpactEngine.goalTimeCard(
            goals: goals.goals, sessions: goalRecords.sessionsByGoal, answers: goalRecords.answers, events: events,
            now: now, calendar: calendar, workingHours: goals.workingHours)
    }

    private static func home(
        _ engine: ImpactEngine, _ events: [CalendarEvent], _ now: Date, _ calendar: Calendar, _ log: ActionLog,
        _ dismissals: Dismissals
    ) -> HomeSnapshot {
        engine.home(events: events, now: now, calendar: calendar, completedCardIDs: log.completedCardIDs,
                    impactsToday: log.impactCount(on: now, calendar: calendar), suppressionRules: dismissals.rules)
    }
}

/// Writes Block time's events: the calendar in the app (`LiveHome`), a stand-in in debug fixtures and tests.
public struct BlockWriter {
    /// Saves an event titled with the goal during the slot, and returns it as a fetch would.
    let add: @MainActor (_ title: String, _ slot: DateInterval) throws -> CalendarEvent
    /// Removes the event Impact created, by its ID.
    let remove: @MainActor (_ eventID: String) throws -> Void

    public init(add: @escaping @MainActor (String, DateInterval) throws -> CalendarEvent,
                remove: @escaping @MainActor (String) throws -> Void) {
        self.add = add
        self.remove = remove
    }

    /// For models that never block time (previews).
    public static var unavailable: BlockWriter { BlockWriter(add: { _, _ in throw BlockUnavailable() }, remove: { _ in }) }

    struct BlockUnavailable: Error {}
}

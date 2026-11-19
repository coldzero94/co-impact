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
    let calendar: Calendar
    private let engine: ImpactEngine
    private var dismissals: Dismissals
    /// Goals and working hours (PRODUCT.md → Goals), edited in goal setup.
    public private(set) var goals: GoalSettings
    /// The goal-time card Home shows below the time-bound cards, if any (PRODUCT.md → Goal-time rules v1).
    public private(set) var goalCard: GoalTimeCard?
    private var goalRecords: GoalRecords
    private let blocks: BlockWriter
    /// The running focus session (PRODUCT.md → Focus blocks), if any.
    private(set) var focus: FocusSession?
    /// The daily log (PRODUCT.md → Daily log): an entry for each Impact recorded, and the user's lines.
    private(set) var dailyLog: DailyLog
    /// The focus block whose session ended with an Impact, until Home has queued the larger Impact moment for it
    /// (UX.md → The Impact moment) and calls `focusImpactShown`.
    private(set) var focusImpact: String?
    /// Receives every Impact after one is recorded or restored, to store them.
    private let saveImpacts: ([String: Date]) -> Void
    /// Receives the dismissals after each dismissal, to store them.
    private let saveDismissals: (Dismissals) -> Void
    /// Receives the goal settings after each change, to store them.
    private let saveGoals: (GoalSettings) -> Void
    /// Receives the goal records whenever they change, to store them.
    private let saveGoalRecords: (GoalRecords) -> Void
    /// Receives the focus session when one starts or ends (nil), to store it.
    private let saveFocus: (FocusSession?) -> Void
    /// Receives the daily log after each change, to store it.
    private let saveDailyLog: (DailyLog) -> Void

    public init(events: [CalendarEvent], now: Date, calendar: Calendar, log: ActionLog = ActionLog(),
                dismissals: Dismissals = Dismissals(), goals: GoalSettings = GoalSettings(),
                goalRecords: GoalRecords = GoalRecords(), blocks: BlockWriter = .unavailable,
                focus: FocusSession? = nil, dailyLog: DailyLog = DailyLog(),
                saveImpacts: @escaping ([String: Date]) -> Void = { _ in },
                saveDismissals: @escaping (Dismissals) -> Void = { _ in },
                saveGoals: @escaping (GoalSettings) -> Void = { _ in },
                saveGoalRecords: @escaping (GoalRecords) -> Void = { _ in },
                saveFocus: @escaping (FocusSession?) -> Void = { _ in },
                saveDailyLog: @escaping (DailyLog) -> Void = { _ in }) throws {
        let engine = try ImpactEngine()
        // Without focus blocks yet: `rebuild` below marks them once the goal records are matched.
        snapshot = Self.home(engine, events, focusBlocks: [:], now, calendar, log, dismissals.pruned(now: now))
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
        self.focus = focus
        self.saveFocus = saveFocus
        self.dailyLog = dailyLog
        self.saveDailyLog = saveDailyLog
        rebuild()
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
        if recorded {
            saveImpacts(log.impacts)
            if let entry = DailyLog.Entry(impactOf: card, at: now, calendar: calendar) { addToDailyLog(entry) }
        }
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
        // Focus blocks show their goal's title, and a removed goal's blocks are plain events again.
        rebuild()
    }

    /// Block time (PRODUCT.md → Block time): saves the card's slot as an event and records it; the next goal-time card
    /// follows at once. Returns the session for Undo. Throws when the calendar refuses; nothing is recorded then.
    func blockTime(_ card: GoalTimeCard) throws -> GoalSession {
        let event = try blocks.add(card.goal.title, card.slot)
        let session = GoalSession(goalID: card.goal.id, eventID: event.id, title: event.title, start: event.start,
                                  end: event.end)
        // Busy at once, before the calendar's change notice brings the next fetch.
        events.append(event)
        goalRecords.block(session)
        rebuild(savingGoalRecords: true)
        return session
    }

    /// Undo while Home offers it after Block time: removes the event Impact created. Throws when the
    /// calendar refuses; the block stays recorded then, as the event stays.
    func undoBlock(_ session: GoalSession) throws {
        try blocks.remove(session.eventID)
        events.removeAll { $0.id == session.eventID }
        goalRecords.undo(session)
        rebuild(savingGoalRecords: true)
    }

    /// Not now: no goal-time card until tomorrow.
    func notNow() {
        goalRecords.notNow(at: now)
        rebuild(savingGoalRecords: true)
    }

    /// Start focus (PRODUCT.md → Focus blocks): starts a session on the focus block, from its Soon phase until it ends,
    /// first ending one that runs on another block. False when the card cannot start one now, or is done: a block
    /// records one Impact, and Home does not show a done card's session. True when its session already runs.
    func startFocus(on card: ImpactCard) -> Bool {
        guard focus?.cardID != card.id else { return true }
        guard !log.completedCardIDs.contains(card.id), let session = FocusSession(card: card, now: now) else { return false }
        finishFocus()
        focus = session
        saveFocus(session)
        rebuild()
        return true
    }

    /// The daily review's days (`DailyLog.days`), newest first.
    var reviewDays: [DailyLog.Day] { dailyLog.days(calendar: calendar) }

    /// The week of `day` as the weekly summary reads it (`WeeklySummary`): its days in order, each with its weekday,
    /// its entries as the review shows them, and its line; nil before the week has three entries, too few to sum up.
    func weekLog(on day: Date) -> String? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return nil }
        let days = reviewDays.filter { week.start <= $0.date && $0.date < week.end }.reversed()
        guard days.reduce(0, { $0 + $1.entries.count }) >= 3 else { return nil }
        // English weekdays, as the app's words are (PRODUCT.md D23), whatever the device's language.
        let weekday = Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX"), timeZone: calendar.timeZone)
            .weekday(.wide)
        return days.map { day in
            ([day.date.formatted(weekday)] + day.entries.map { "- \($0.text)" } + (day.line.map { ["Line: \($0)"] } ?? []))
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// The day's one line, as stored.
    func line(on day: Date) -> String { dailyLog.lines[DailyLog.key(for: day, calendar: calendar)] ?? "" }

    /// The daily review's one line for `day` (PRODUCT.md → Daily log), stored when it changed.
    func setLine(_ text: String, on day: Date) {
        let before = dailyLog
        dailyLog.setLine(text, on: day, calendar: calendar)
        if dailyLog != before { saveDailyLog(dailyLog) }
    }

    /// UX.md → Home: the "Today" row that opens the daily review, from 18:00, or once today's last card is done.
    var showsTodayRow: Bool {
        calendar.component(.hour, from: now) >= 18
            || (snapshot.nextUp == nil && snapshot.impactsToday > 0)
    }

    /// Home queued the moment for `focusImpact`.
    func focusImpactShown() {
        focusImpact = nil
    }

    /// End focus: the session ends now, and records the block's Impact if it lasted 10 minutes or more (returns true
    /// then). Ending early is never scolded (PRODUCT.md → Focus blocks).
    func endFocus() -> Bool {
        let recorded = finishFocus()
        rebuild()
        return recorded
    }

    /// What the widgets and background refresh need to see cards as Home does (`SurfaceState`): the Impacts of the
    /// last two days or of events still fetched (e.g. a multi-day event joined on its first day, or a meeting joined
    /// and then moved), the dismissals' rules, the run links' secret, the focus blocks, and the running session.
    func surfaceState(runToken: String) -> SurfaceState {
        let since = now.addingTimeInterval(-2 * 86_400)
        let fetched = Set(events.map(\.id))
        return SurfaceState(completed: log.impacts.filter { $0.value > since || fetched.contains($0.key) },
                            suppressionRules: dismissals.rules, runToken: runToken, focusBlocks: focusBlocks, focus: focus)
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

    /// Matches the blocked sessions to the calendar and stores them if that (or the caller, with `savingGoalRecords`)
    /// changed them; builds the snapshot with their focus blocks; ends a focus session at its end (the block's end when
    /// focus started), or once its block is no longer in its Soon or Now phase on Home (moved, deleted, or
    /// dismissed); and picks the goal-time card.
    private func rebuild(savingGoalRecords: Bool = false) {
        let matched = goalRecords.matched(events: events, now: now, calendar: calendar)
        if savingGoalRecords || matched != goalRecords {
            goalRecords = matched
            saveGoalRecords(matched)
        }
        snapshot = Self.home(engine, events, focusBlocks: focusBlocks, now, calendar, log, dismissals)
        if let focus, !focus.runs(in: snapshot, now: now) {
            if finishFocus() { snapshot = Self.home(engine, events, focusBlocks: focusBlocks, now, calendar, log, dismissals) }
        }
        goalCard = ImpactEngine.goalTimeCard(
            goals: goals.goals, sessions: goalRecords.sessionsByGoal, lastNotNow: goalRecords.lastNotNow, events: events,
            now: now, calendar: calendar, workingHours: goals.workingHours)
    }

    /// Ends the running session, if any: stores that none runs, and records its Impact (returns true then).
    @discardableResult
    private func finishFocus() -> Bool {
        guard let session = focus else { return false }
        focus = nil
        saveFocus(nil)
        guard log.recordFocus(session, endedAt: now) else { return false }
        saveImpacts(log.impacts)
        addToDailyLog(DailyLog.Entry(session: session, endedAt: now, calendar: calendar))
        focusImpact = session.cardID
        return true
    }

    private func addToDailyLog(_ entry: DailyLog.Entry) {
        dailyLog.add(entry)
        saveDailyLog(dailyLog)
    }

    /// Focus blocks by event ID (`CalendarEvent.focusGoal`): the sessions Impact blocked for goals the user still
    /// has, titled with the goal; a removed goal's blocks are plain events again.
    private var focusBlocks: [String: String] {
        let titles = Dictionary(goals.goals.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(goalRecords.sessions.compactMap { session in titles[session.goalID].map { (session.eventID, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    private static func home(
        _ engine: ImpactEngine, _ events: [CalendarEvent], focusBlocks: [String: String], _ now: Date,
        _ calendar: Calendar, _ log: ActionLog, _ dismissals: Dismissals
    ) -> HomeSnapshot {
        // As every surface marks them (`SurfaceState.focusBlocks`), or background refresh ends Home's activities.
        engine.home(events: NextCards.marked(events, focusBlocks: focusBlocks), now: now, calendar: calendar,
                    completedCardIDs: log.completedCardIDs, impactsToday: log.impactCount(on: now, calendar: calendar),
                    suppressionRules: dismissals.rules)
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

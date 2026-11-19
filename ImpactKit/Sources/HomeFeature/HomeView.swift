import Accessibility
import CalendarSources
import ImpactEngine
import LiveSurfaces
import os
import SwiftUI

/// Home (UX.md → Home): summary and Impact ring, Next up, Later today, Tomorrow morning. Tapping a card
/// opens its detail; running a primary action once it counts (`ActionLog.countsFrom`), or a focus session of 10
/// minutes or more, records an Impact and plays the Impact moment; swiping a card dismisses it (UX.md → Dismissing).
public struct HomeView: View {
    let model: HomeModel
    @State private var selected: ImpactCard?
    @State private var failed: ActionKind?
    @State private var momentFrames = MomentFrames()
    /// An Impact recorded when its action ran; it plays once Home is in front again with no sheet open.
    @State private var pending: Moment?
    @State private var flying: Moment?
    @State private var landings = 0
    /// The ring's brief glow after a focus session's Impact lands.
    @State private var glowing = false
    /// When a tap or Home last changed the button under the finger: an Impact moves Next up on, and Start focus and End
    /// focus take each other's place. Uptime, which clock changes do not move (not `HomeModel.now`, which moves only when
    /// Home refreshes).
    @State private var swapped: TimeInterval?
    @State private var settingUpGoals = false
    /// Block time's session, while its card shows "Blocked" with Undo (UX.md → Home: 5 seconds, 15 with VoiceOver).
    @State private var justBlocked: JustBlocked?
    @State private var blockings = 0
    @State private var blockFailed = false
    /// Block time failed for want of a writable default calendar, which the user can choose in Settings.
    @State private var noWritableCalendar = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var undoFailed = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = 46.0

    /// A card's action a widget, Live Activity, or App Intent asked Impact to run (`RunRequest`); Home runs it and
    /// clears it.
    @Binding private var runRequest: RunRequest?

    public init(model: HomeModel, runRequest: Binding<RunRequest?> = .constant(nil)) {
        self.model = model
        _runRequest = runRequest
    }

    public var body: some View {
        let snapshot = model.snapshot
        NavigationStack {
            List {
                Section {
                    if let next = snapshot.nextUp {
                        NextUpCard(card: next, now: model.now, session: model.focus.flatMap { $0.cardID == next.id ? $0 : nil },
                                   details: { selected = next }, primary: { action in
                            // Within a second of an Impact, Next up already shows the next card (and after End focus,
                            // Start focus again), so a tap is treated as the second half of a double tap and ignored. A
                            // later one first plays a moment still queued because the app never left (see playPending).
                            if justSwapped { return }
                            playPending()
                            run(action, on: next) { failed = $0 }
                        }, endFocus: endFocus)
                            .recordingFrame { momentFrames.cards[next.id] = $0 }
                            // A new view per card, so the promoted card records its own frame.
                            .id(next.id)
                            .dismissible(similar: next.kind != .focusBlock) { model.dismiss(next, similar: $0) }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nothing needs you today.")
                                .font(.title3.weight(.semibold))
                            if let next = snapshot.next {
                                Text("Next: \(next.start, format: .dateTime.weekday(.abbreviated).hour().minute()) · \(next.title)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: .rect(cornerRadius: 24))
                    }
                } header: {
                    // A header, not a row: rows clip the large title's first glyph at the cell's edge.
                    header(snapshot).textCase(nil).foregroundStyle(.primary).padding(.bottom, 16)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                section("Later today", snapshot.laterToday, done: snapshot.doneCardIDs)
                goalSection
                section("Tomorrow morning", snapshot.tomorrowMorning, done: snapshot.doneCardIDs)
                if model.offersGoalSetup {
                    Section {
                        // UX.md → Onboarding: a quiet row, offered once.
                        Button {
                            model.goalSetupOffered()
                            settingUpGoals = true
                        } label: {
                            // The section headers' gray: quiet, at about 5.5:1 in light mode.
                            Label("Set up to three goals for this year", systemImage: "flag")
                                .foregroundStyle(Color.primary.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Hide", systemImage: "xmark", role: .destructive) { model.goalSetupOffered() }
                        }
                    }
                    .listRowBackground(Color.card)
                }
            }
            .homeListStyle()
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .overlay {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    if let flying, let from = flying.from, let to = momentFrames.ring {
                        ImpactToken(symbol: flying.symbol, from: from.offsetBy(dx: -origin.x, dy: -origin.y),
                                    to: to.offsetBy(dx: -origin.x, dy: -origin.y), onLanded: land)
                            .id(flying.id)
                    }
                }
                .allowsHitTesting(false)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Goals", systemImage: "flag") { settingUpGoals = true }
                }
            }
        }
        .sheet(isPresented: $settingUpGoals, onDismiss: playPending) { GoalSetupView(model: model) }
        .sheet(item: $selected, onDismiss: playPending) { card in
            CardDetailView(card: card, model: model, run: { action, failed in
                // Card detail swaps Start focus and End focus in place too. Only taps: a run request never waits.
                if action.kind == .startFocus, justSwapped { return }
                run(action, on: card, failed: failed)
            }, endFocus: endFocus)
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        .actionFailureAlert($failed)
        .onChange(of: runRequest, initial: true) {
            guard let request = runRequest else { return }
            runRequest = nil
            guard let card = model.runnableCard(id: request.cardID), let action = request.pick(from: card) else {
                // Dismissed, expired, not listed (yet), or gone since the surface showed it: Home shows
                // what is left. A done card Home still lists runs again (e.g. to rejoin).
                homeLog.notice("A run request for card \(request.cardID, privacy: .private) found nothing to run")
                return
            }
            run(action, on: card) { failed = $0 }
        }
        .sensoryFeedback(.success, trigger: landings)
        .sensoryFeedback(.success, trigger: blockings)
        .task(id: justBlocked) {
            guard justBlocked != nil else { return }
            // VoiceOver first reads the announcement, then needs time to reach Undo.
            try? await Task.sleep(for: .seconds(voiceOver ? 15 : 5))
            if !Task.isCancelled { justBlocked = nil }
        }
        .alert("Couldn't add to your calendar", isPresented: $blockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noWritableCalendar ? "Choose a default calendar in Settings → Apps → Calendar, then try again."
                 : "Try again in a moment.")
        }
        .alert("Couldn't remove the block", isPresented: $undoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Delete it in Calendar.")
        }
        .onChange(of: scenePhase) { playPending() }
        // A focus session ended with an Impact: by End focus, or with its block, possibly while Impact was away.
        // Initial too: a session whose block ended while Impact was not running ends at launch.
        .onChange(of: model.focusImpact, initial: true) {
            guard let cardID = model.focusImpact else { return }
            model.focusImpactShown()
            pending = Moment(symbol: ActionKind.startFocus.symbol, from: momentFrames.cards[cardID], large: true)
            swapped = ProcessInfo.processInfo.systemUptime
            playPending()
        }
        .onChange(of: model.snapshot) { _, snapshot in
            // An open detail follows its card as Home refreshes, and closes once the card is gone (e.g. the event
            // was canceled, deleted, or moved out of what Home lists, no longer needs prep, got a new ID, or the
            // card expired), so no action runs on a stale card.
            guard let shown = selected else { return }
            selected = snapshot.cards.first { $0.id == shown.id }
        }
    }

    /// The goal-time card (UX.md → Home): "Blocked" with Undo for a while after Block time, then the next one; a swipe
    /// offers Not now.
    @ViewBuilder
    private var goalSection: some View {
        if let shown = justBlocked {
            Section {
                GoalCardView(card: shown.card, now: model.now, blocked: true, block: {}) {
                    do {
                        try model.undoBlock(shown.session)
                    } catch {
                        homeLog.error("Undo of Block time failed: \(error.logged, privacy: .public)")
                        undoFailed = true
                    }
                    justBlocked = nil
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.card)
        } else if let card = model.goalCard {
            Section {
                GoalCardView(card: card, now: model.now, blocked: false, block: {
                    do {
                        justBlocked = JustBlocked(card: card, session: try model.blockTime(card))
                        blockings += 1
                        // The button VoiceOver was on is gone: say what happened (UX.md → Motion).
                        AccessibilityNotification.Announcement(
                            "Blocked \(GoalCardView.day(card.slot.start, now: model.now, spoken: true)) for \(card.goal.title)"
                        ).post()
                    } catch {
                        homeLog.error("Block time failed: \(error.logged, privacy: .public)")
                        noWritableCalendar = (error as? BlockError) == .noWritableCalendar
                        blockFailed = true
                    }
                }, undo: {})
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Not now", systemImage: "moon.zzz") { model.notNow() }
                        .tint(.gray)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.card)
        }
    }

    private func header(_ snapshot: HomeSnapshot) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.title.bold())
                Text(summaryLine(cards: (snapshot.nextUp == nil ? 0 : 1) + snapshot.laterToday.count,
                                 eventsLeft: snapshot.eventsLeftToday))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            // The ring fills the moment's segment only when its token lands.
            let unshown = (pending == nil ? 0 : 1) + (flying == nil ? 0 : 1)
            ImpactRing(filled: max(0, snapshot.impactsToday - unshown), segments: snapshot.ringSegments)
                .frame(width: ringSize, height: ringSize)
                .shadow(color: Color.accentColor.opacity(glowing ? 0.9 : 0), radius: glowing ? 14 : 0)
                .recordingFrame { momentFrames.ring = $0 }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ cards: [ImpactCard], done: Set<String>) -> some View {
        if !cards.isEmpty {
            Section {
                ForEach(cards) { card in
                    Button { selected = card } label: { CardRow(card: card, done: done.contains(card.id)) }
                        .buttonStyle(RowButtonStyle())
                        .recordingFrame { momentFrames.cards[card.id] = $0 }
                        .dismissible(similar: card.kind != .focusBlock) { model.dismiss(card, similar: $0) }
                }
            } header: {
                // The list's secondary header color is about 3.3:1 on the light grouped background; 60% of the
                // primary color is about 5.5:1 in light and over 7:1 in dark mode.
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.6))
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.card)
        }
    }

    /// Runs the action and, when it records an Impact, queues the moment from the card's current frame. Start focus
    /// starts a session in Home instead; its Impact comes when the session ends (`focusImpact`).
    private func run(_ action: ImpactAction, on card: ImpactCard, failed: @escaping (ActionKind) -> Void) {
        if action.kind == .startFocus {
            // Already running (e.g. the Next up control pressed during it): nothing changes, nothing to announce.
            if model.focus?.cardID == card.id { return }
            if model.startFocus(on: card) {
                swapped = ProcessInfo.processInfo.systemUptime
                // The button VoiceOver was on now ends the session: say what happened (UX.md → Motion).
                AccessibilityNotification.Announcement("Focus started on \(card.title)").post()
            } else {
                // Home offers Start focus only from the block's Soon phase on (`ImpactCard.offers`).
                homeLog.notice("Start focus on card \(card.id, privacy: .private) outside its Soon or Now phase, or done; nothing started")
            }
            return
        }
        let from = momentFrames.cards[card.id]
        action.kind.run(with: openURL) { opened in
            guard opened else { return failed(action.kind) }
            if model.record(action, on: card) {
                pending = Moment(symbol: card.symbol, from: from)
                swapped = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    /// Event-card actions leave the app on iPhone, so the moment waits until Home is in front again with no
    /// sheet open (UX.md → The Impact moment). If an action never left, the next Next up tap or sheet close
    /// plays it.
    private func playPending() {
        guard scenePhase == .active, selected == nil, !settingUpGoals, flying == nil, let moment = pending else { return }
        if reduceMotion || moment.from == nil || momentFrames.ring == nil {
            land()
        } else {
            pending = nil
            flying = moment
        }
    }

    /// End focus, from Next up or card detail. A session of 10 minutes or more plays its Impact moment
    /// (`focusImpact`), which VoiceOver hears; a shorter one just ends, never scolded (PRODUCT.md → Focus blocks).
    /// End focus takes Start focus's place, and back: within a second of either, a tap is the second half of a double
    /// tap.
    private func endFocus() {
        if justSwapped { return }
        swapped = ProcessInfo.processInfo.systemUptime
        if !model.endFocus() { AccessibilityNotification.Announcement("Focus ended").post() }
    }

    /// Whether a tap now is the second half of a double tap on a button that just changed (`swapped`).
    private var justSwapped: Bool {
        swapped.map { ProcessInfo.processInfo.systemUptime - $0 < 1 } ?? false
    }

    /// Fills the ring's segment (a cross-fade under Reduce Motion), plays the haptic, and tells VoiceOver. A focus
    /// session's Impact also makes the ring glow briefly.
    private func land() {
        let large = (flying ?? pending)?.large ?? false
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.4)) {
            // A token landing keeps an Impact recorded during its flight queued; playPending below plays
            // it now if Home is in front with no sheet open, otherwise at its next trigger.
            if flying == nil { pending = nil }
            flying = nil
            if large { glowing = true }
        }
        if large {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.easeOut(duration: 0.6)) { glowing = false }
            }
        }
        landings += 1
        let shown = model.snapshot.impactsToday - (pending == nil ? 0 : 1)
        AccessibilityNotification.Announcement("Impact recorded. \(shown) today.").post()
        playPending()
    }
}

/// Where Impact moments start (card frames, by card ID) and land (the ring), in global coordinates. A
/// non-observable reference: scrolling moves these frames all the time and writing them redraws nothing;
/// `@State` only keeps the instance alive.
@MainActor
private final class MomentFrames {
    var cards: [String: CGRect] = [:]
    var ring: CGRect?
}

private struct JustBlocked: Equatable {
    let card: GoalTimeCard
    let session: GoalSession
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
    }
}

extension View {
    /// Reports this view's frame in global coordinates.
    fileprivate func recordingFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: action)
    }

    /// Grouped cards on the page background, 28 points between sections (the macOS build is for tests only).
    fileprivate func homeListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped).listSectionSpacing(28)
        #else
        listStyle(.inset)
        #endif
    }

    /// UX.md → Dismissing: a full swipe means Not needed; the second button, when `similar`, mutes events like this
    /// one. A focus block offers only Not needed: muting its title would hide every block of its goal.
    fileprivate func dismissible(similar: Bool, _ dismiss: @escaping (_ similar: Bool) -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Not needed", systemImage: "xmark", role: .destructive) { dismiss(false) }
            if similar {
                Button("Don't suggest for events like this", systemImage: "bell.slash") { dismiss(true) }
                    .tint(.gray)
            }
        }
    }
}

/// Next up: the accent card with a large countdown and the primary action (UX.md → Home). During a focus session on
/// the card, the time left and End focus instead.
struct NextUpCard: View {
    let card: ImpactCard
    let now: Date
    var session: FocusSession?
    let details: () -> Void
    let primary: (ImpactAction) -> Void
    var endFocus: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 72.0

    var body: some View {
        let countdown = Countdown(to: card.start, now: now)
        let topRow = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
        VStack(alignment: .leading, spacing: 4) {
            Button(action: details) {
                VStack(alignment: .leading, spacing: 4) {
                    topRow {
                        Label(card.keyFact, systemImage: card.symbol)
                        if !typeSize.isAccessibilitySize { Spacer() }
                        if let session {
                            Text("until \(session.end, format: .dateTime.hour().minute())").monospacedDigit()
                        } else if countdown != .clock {
                            Text(card.start, format: .dateTime.hour().minute()).monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    Group {
                        if let session { timeLeft(session) } else { countdownText(countdown) }
                    }
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 6)
                    Text(card.title).font(.title2.weight(.semibold))
                    if let session {
                        Text("Focusing since \(session.start, format: .dateTime.hour().minute())").opacity(0.9)
                    } else {
                        Text(card.answer).opacity(0.9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if session != nil {
                button("End focus", symbol: "stop.fill", run: endFocus)
            } else if let action = card.primaryAction, card.offers(action, now: now) {
                button(action.kind.label, symbol: action.kind.symbol) { primary(action) }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill.gradient, in: .rect(cornerRadius: 28))
    }

    private var fill: Color { .accentFill(colorScheme) }

    private func button(_ label: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(label, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white, in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(fill)
        .padding(.top, 16)
        .accessibilityLabel("\(label), \(card.title)")
    }

    /// Minutes left in the session, rounded up, so the last minute shows 1; Home refreshes each minute.
    private func timeLeft(_ session: FocusSession) -> some View {
        let minutes = max(1, Int((session.end.timeIntervalSince(now) / 60).rounded(.up)))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(minutes, format: .number).font(.system(size: countdownSize, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("min left").font(.title2.weight(.semibold)).opacity(0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(minutes) \(minutes == 1 ? "minute" : "minutes") left")
    }

    @ViewBuilder
    private func countdownText(_ countdown: Countdown) -> some View {
        let big = Font.system(size: countdownSize, weight: .bold, design: .rounded)
        switch countdown {
        case .now:
            Text("Now").font(big)
        case .minutes(let minutes):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(minutes, format: .number).font(big).monospacedDigit()
                Text("min").font(.title2.weight(.semibold)).opacity(0.9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("In \(minutes) \(minutes == 1 ? "minute" : "minutes")")
        case .clock:
            Text(card.start, format: .dateTime.hour().minute()).font(big).monospacedDigit()
        }
    }
}

/// A departure-board row: time, title, and the key fact; done rows show a checkmark instead.
struct CardRow: View {
    let card: ImpactCard
    let done: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = 72.0

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(card.start, format: .dateTime.hour().minute())
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: typeSize.isAccessibilitySize ? nil : timeWidth, alignment: .leading)
            Text(card.title).fontWeight(.medium).foregroundStyle(done ? .secondary : .primary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if done {
                Label("Done", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.tint)
            } else {
                Label(card.keyFact, systemImage: card.symbol).font(.subheadline).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon) // not List's icon column
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 16 } // separators start at the row's time
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    /// The accent behind white text. The dark-mode accent is light for tinting, so it is darkened to keep
    /// white text readable.
    static func accentFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.accentColor.mix(with: .black, by: 0.45) : .accentColor
    }

    static var page: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var card: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#if DEBUG
#Preview("09:48, Next up in 12 min") { sampleHome(hour: 9.8) }
#Preview("08:00, done row, clock countdown") { sampleHome(hour: 8) }
#Preview("19:00, nothing left, Tomorrow morning") { sampleHome(hour: 19) }
#Preview("21:00, Next line") { sampleHome(hour: 21) }

@MainActor @ViewBuilder
private func sampleHome(hour: Double) -> some View {
    switch Result(catching: { try HomeFixtures.sample(at: hour) }) {
    case .success(let model): HomeView(model: model)
    case .failure(let error): Text("Fixture failed: \(error.localizedDescription)")
    }
}
#endif

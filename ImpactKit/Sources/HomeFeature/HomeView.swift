import Accessibility
import ImpactEngine
import LiveSurfaces
import os
import SwiftUI

/// Home (UX.md → Home): summary and Impact ring, Next up, Later today, Tomorrow morning. Tapping a card
/// opens its detail; running a primary action once it counts (`ActionLog.countsFrom`) records an Impact and
/// plays the Impact moment; swiping a card dismisses it (UX.md → Dismissing).
public struct HomeView: View {
    let model: HomeModel
    @State private var selected: ImpactCard?
    @State private var failed: ActionKind?
    @State private var momentFrames = MomentFrames()
    /// An Impact recorded when its action ran; it plays once Home is in front again with no sheet open.
    @State private var pending: Moment?
    @State private var flying: Moment?
    @State private var landings = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = 46.0

    /// A card whose primary action a Live Activity asked Impact to run (`LiveCard.runURL`); Home runs it and
    /// clears it.
    @Binding private var runCardID: String?

    public init(model: HomeModel, runCardID: Binding<String?> = .constant(nil)) {
        self.model = model
        _runCardID = runCardID
    }

    public var body: some View {
        let snapshot = model.snapshot
        List {
            Section {
                if let next = snapshot.nextUp {
                    NextUpCard(card: next, now: model.now, details: { selected = next }, primary: { action in
                        // Within a second of an Impact, Next up already shows the next card, so a tap is
                        // treated as the second half of a double tap and ignored. A later one first plays a
                        // moment still queued because the app never left (see playPending).
                        if let pending, ProcessInfo.processInfo.systemUptime - pending.recorded < 1 { return }
                        playPending()
                        run(action, on: next) { failed = $0 }
                    })
                        .recordingFrame { momentFrames.cards[next.id] = $0 }
                        // A new view per card, so the promoted card records its own frame.
                        .id(next.id)
                        .dismissible { model.dismiss(next, similar: $0) }
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
            section("Tomorrow morning", snapshot.tomorrowMorning, done: snapshot.doneCardIDs)
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
        .sheet(item: $selected, onDismiss: playPending) { card in
            CardDetailView(card: card, model: model) { action, failed in run(action, on: card, failed: failed) }
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        .actionFailureAlert($failed)
        .onChange(of: runCardID, initial: true) {
            guard let id = runCardID else { return }
            runCardID = nil
            // Widgets and Live Activities can show a card Home does not list yet (tomorrow's, before 18:00).
            let cards = model.snapshot.cards + model.snapshot.liveActivityCards
            guard let card = cards.first(where: { $0.id == id }), let primary = card.primaryAction else {
                // Dismissed, expired, or gone since the activity was scheduled: Home shows what is left. A done card
                // is still listed and runs again (e.g. to rejoin).
                homeLog.notice("A Live Activity asked to run card \(id, privacy: .private), which Home no longer lists")
                return
            }
            run(primary, on: card) { failed = $0 }
        }
        .sensoryFeedback(.success, trigger: landings)
        .onChange(of: scenePhase) { playPending() }
        .onChange(of: model.snapshot) { _, snapshot in
            // An open detail follows its card as Home refreshes, and closes once the card is gone (e.g. the event
            // was canceled, deleted, or moved out of what Home lists, no longer needs prep, got a new ID, or the
            // card expired), so no action runs on a stale card.
            guard let shown = selected else { return }
            selected = snapshot.cards.first { $0.id == shown.id }
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
                        .dismissible { model.dismiss(card, similar: $0) }
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

    /// Runs the action and, when it records an Impact, queues the moment from the card's current frame.
    private func run(_ action: ImpactAction, on card: ImpactCard, failed: @escaping (ActionKind) -> Void) {
        let from = momentFrames.cards[card.id]
        action.kind.run(with: openURL) { opened in
            guard opened else { return failed(action.kind) }
            if model.record(action, on: card) { pending = Moment(symbol: card.symbol, from: from) }
        }
    }

    /// Event-card actions leave the app on iPhone, so the moment waits until Home is in front again with no
    /// sheet open (UX.md → The Impact moment). If an action never left, the next Next up tap or sheet close
    /// plays it.
    private func playPending() {
        guard scenePhase == .active, selected == nil, flying == nil, let moment = pending else { return }
        if reduceMotion || moment.from == nil || momentFrames.ring == nil {
            land()
        } else {
            pending = nil
            flying = moment
        }
    }

    /// Fills the ring's segment (a cross-fade under Reduce Motion), plays the haptic, and tells VoiceOver.
    private func land() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.4)) {
            // A token landing keeps an Impact recorded during its flight queued; playPending below plays
            // it now if Home is in front with no sheet open, otherwise at its next trigger.
            if flying == nil { pending = nil }
            flying = nil
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

    /// UX.md → Dismissing: a full swipe means Not needed; the second button mutes events like this one.
    fileprivate func dismissible(_ dismiss: @escaping (_ similar: Bool) -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Not needed", systemImage: "xmark", role: .destructive) { dismiss(false) }
            Button("Don't suggest for events like this", systemImage: "bell.slash") { dismiss(true) }
                .tint(.gray)
        }
    }
}

/// Next up: the accent card with a large countdown and the primary action (UX.md → Home).
struct NextUpCard: View {
    let card: ImpactCard
    let now: Date
    let details: () -> Void
    let primary: (ImpactAction) -> Void
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
                        if countdown != .clock {
                            Text(card.start, format: .dateTime.hour().minute()).monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    countdownText(countdown).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 6)
                    Text(card.title).font(.title2.weight(.semibold))
                    Text(card.answer).opacity(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let action = card.primaryAction {
                Button { primary(action) } label: {
                    Label(action.kind.label, systemImage: action.kind.symbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(fill)
                .padding(.top, 16)
                .accessibilityLabel("\(action.kind.label), \(card.title)")
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill.gradient, in: .rect(cornerRadius: 28))
    }

    private var fill: Color { .accentFill(colorScheme) }

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

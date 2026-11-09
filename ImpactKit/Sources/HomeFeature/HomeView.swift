import Accessibility
import ImpactEngine
import SwiftUI

/// Home (UX.md → Home): summary and Impact ring, Next up, Later today, Tomorrow morning. Tapping a card
/// opens its detail; running a primary action records an Impact and plays the Impact moment.
public struct HomeView: View {
    let model: HomeModel
    @State private var selected: ImpactCard?
    @State private var failed: ActionKind?
    /// Card frames by card ID in the content's coordinate space: where a moment starts.
    @State private var frames: [String: CGRect] = [:]
    /// The ring's frame in the same space: where a moment lands; nil skips the flight.
    @State private var ringFrame: CGRect?
    /// An Impact recorded when its action ran; it plays once Home is in front again with no sheet open.
    @State private var pending: Moment?
    @State private var flying: Moment?
    @State private var landings = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = 46.0

    nonisolated static let space = "home"

    public init(model: HomeModel) {
        self.model = model
    }

    public var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(snapshot)
                if let next = snapshot.nextUp {
                    NextUpCard(card: next, now: model.now, details: { selected = next }, primary: { action in
                        // Within a second of an Impact, Next up already shows the next card, so a tap is
                        // treated as the second half of a double tap and ignored. A later one first plays a
                        // moment still queued because the app never left (see playPending).
                        if let pending, ProcessInfo.processInfo.systemUptime - pending.recorded < 1 { return }
                        playPending()
                        run(action, on: next) { failed = $0 }
                    })
                        .recordingFrame { frames[next.id] = $0 }
                        // A new view per card, so the promoted card records its own frame.
                        .id(next.id)
                } else {
                    // shortcut: no "Next:" line until events past the horizon arrive (roadmap step 7).
                    Text("Nothing needs you today.")
                        .font(.title3.weight(.semibold))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: .rect(cornerRadius: 24))
                }
                section("Later today", snapshot.laterToday, done: snapshot.doneCardIDs)
                section("Tomorrow morning", snapshot.tomorrowMorning, done: snapshot.doneCardIDs)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay {
                if let flying, let from = flying.from, let to = ringFrame {
                    ImpactToken(symbol: flying.symbol, from: from, to: to, onLanded: land).id(flying.id)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .background(Color.page)
        .sheet(item: $selected, onDismiss: playPending) { card in
            CardDetailView(card: card, model: model) { action, failed in run(action, on: card, failed: failed) }
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        .actionFailureAlert($failed)
        .sensoryFeedback(.success, trigger: landings)
        .onChange(of: scenePhase) { playPending() }
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
                .recordingFrame { ringFrame = $0 }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ cards: [ImpactCard], done: Set<String>) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button { selected = card } label: { CardRow(card: card, done: done.contains(card.id)) }
                            .buttonStyle(RowButtonStyle())
                            .recordingFrame { frames[card.id] = $0 }
                    }
                }
                .background(Color.card, in: .rect(cornerRadius: 18))
                .clipShape(.rect(cornerRadius: 18))
            }
        }
    }

    /// Runs the action and, when it records an Impact, queues the moment from the card's current frame.
    private func run(_ action: ImpactAction, on card: ImpactCard, failed: @escaping (ActionKind) -> Void) {
        let from = frames[card.id]
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
        if reduceMotion || moment.from == nil || ringFrame == nil {
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

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
    }
}

extension View {
    /// Reports this view's frame in Home's content space, which scrolling does not change.
    fileprivate func recordingFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(HomeView.space)) }, action: action)
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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

@MainActor @ViewBuilder
private func sampleHome(hour: Double) -> some View {
    switch Result(catching: { try HomeFixtures.sample(at: hour) }) {
    case .success(let model): HomeView(model: model)
    case .failure(let error): Text("Fixture failed: \(error.localizedDescription)")
    }
}
#endif

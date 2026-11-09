import ImpactEngine
import SwiftUI

/// Home (UX.md → Home): summary and Impact ring, Next up, Later today, Tomorrow morning.
public struct HomeView: View {
    let snapshot: HomeSnapshot
    let now: Date
    let impactsToday: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSize = 46.0

    public init(snapshot: HomeSnapshot, now: Date, impactsToday: Int) {
        self.snapshot = snapshot
        self.now = now
        self.impactsToday = impactsToday
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let next = snapshot.nextUp {
                    NextUpCard(card: next, now: now)
                } else {
                    Text("Nothing needs you today.")
                        .font(.title3.weight(.semibold))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: .rect(cornerRadius: 24))
                }
                section("Later today", snapshot.laterToday)
                section("Tomorrow morning", snapshot.tomorrowMorning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.page)
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.title.bold())
                Text(summaryLine(cards: (snapshot.nextUp == nil ? 0 : 1) + snapshot.laterToday.count,
                                 eventsLeft: snapshot.eventsLeftToday))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            ImpactRing(filled: impactsToday, segments: snapshot.ringSegments)
                .frame(width: ringSize, height: ringSize)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ cards: [ImpactCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        if index > 0 { Divider().padding(.leading, 16) }
                        CardRow(card: card, done: snapshot.doneCardIDs.contains(card.id))
                    }
                }
                .background(Color.card, in: .rect(cornerRadius: 18))
            }
        }
    }
}

/// Next up: the accent card with a large countdown and the primary action (Draft C, UX.md → Home).
struct NextUpCard: View {
    let card: ImpactCard
    let now: Date
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 72.0

    var body: some View {
        let countdown = Countdown(to: card.start, now: now)
        let topRow = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
        VStack(alignment: .leading, spacing: 4) {
            topRow {
                Label(card.keyFact, systemImage: card.symbol)
                if !typeSize.isAccessibilitySize { Spacer() }
                if countdown != .clock {
                    Text(card.start, format: .dateTime.hour().minute()).monospacedDigit()
                }
            }
            .font(.subheadline.weight(.semibold))
            countdownText(countdown).padding(.top, 6)
            Text(card.title).font(.title2.weight(.semibold))
            Text(card.answer).opacity(0.9)
            if let action = card.actions.first {
                // shortcut: actions are wired in roadmap step 6 (card detail and actions).
                Button {} label: {
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

    /// The dark-mode accent is light for tinting, so the card darkens it to keep white text readable.
    private var fill: Color {
        colorScheme == .dark ? Color.accentColor.mix(with: .black, by: 0.45) : .accentColor
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension Color {
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

#Preview("Morning") {
    if let fixture = try? HomeFixtures.morning() {
        HomeView(snapshot: fixture.snapshot, now: fixture.now, impactsToday: fixture.impactsToday)
    }
}

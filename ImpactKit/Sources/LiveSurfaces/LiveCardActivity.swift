#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// A card's Live Activity (UX.md → System surfaces): the Now phase only. Its one button opens Impact, which runs
/// the primary action. StandBy shows the Lock Screen layout; the Watch Smart Stack and CarPlay show the small one,
/// without the button (it does nothing in CarPlay, and the car is glance-only).
public struct LiveCardActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveCard.self) { context in
            ActivityContent(card: context.attributes, stale: context.isStale)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            let card = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: card.symbol).font(.title2).foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(card: card, stale: context.isStale).font(.title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(card.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(card.answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        ActionLink(card: card)
                    }
                }
            } compactLeading: {
                // With limited width the pair must fit a 28-pt circle: the ring alone, the empty trailing side hidden.
                LimitedWidth { limited in
                    if limited {
                        TimeRing(card: card)
                    } else {
                        Image(systemName: card.symbol).foregroundStyle(.indigo).accessibilityLabel(card.title)
                    }
                }
            } compactTrailing: {
                LimitedWidth { limited in
                    if !limited {
                        // A dimmed screen showed "8 minutes" here in the simulator: shrink rather than truncate.
                        Countdown(card: card, stale: context.isStale).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: 64)
                    }
                }
            } minimal: {
                TimeRing(card: card)
            }
            .keylineTint(.indigo)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// The Lock Screen and StandBy layout, or the small one on the Watch and in CarPlay.
private struct ActivityContent: View {
    let card: LiveCard
    let stale: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: card.symbol).foregroundStyle(.indigo).accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Countdown(card: card, stale: stale).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(card.title).font(.headline).lineLimit(1)
                Text(card.answer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
        } else {
            LockScreenView(card: card, stale: stale)
        }
    }
}

/// Time left to the start as a ring around the card's symbol, drawn by the system: it fits the 28-pt circle of
/// the minimal and limited-width views, where timer text would truncate. Empty from the start on.
private struct TimeRing: View {
    let card: LiveCard

    var body: some View {
        ProgressView(timerInterval: card.nowPhase.lowerBound...card.start, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            Image(systemName: card.symbol).font(.caption2.weight(.semibold))
        }
        .progressViewStyle(.circular)
        .tint(.indigo)
        .foregroundStyle(.indigo)
        .accessibilityLabel(Text("\(card.title), \(card.start, format: .dateTime.hour().minute())"))
    }
}

/// Whether the Dynamic Island draws compact and minimal views with limited width (iOS 27: landscape, or two
/// activities on iPhone 18 Pro); never before iOS 27.
private struct LimitedWidth<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        if #available(iOS 27, *) { Reader(content: content) } else { content(false) }
    }

    @available(iOS 27, *)
    private struct Reader: View {
        @Environment(\.isDynamicIslandLimitedInWidth) private var limited
        let content: (Bool) -> Content

        var body: some View { content(limited) }
    }
}

private struct LockScreenView: View {
    let card: LiveCard
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: card.symbol).font(.title3).foregroundStyle(.indigo)
                    .frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.headline).lineLimit(1)
                    Text(card.answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Countdown(card: card, stale: stale).font(.title2.weight(.semibold))
            }
            ActionLink(card: card)
        }
        .padding(14)
    }
}

/// Time to the start, then time since it (m:ss), drawn by the system so it moves without updates. Once the Now
/// phase has passed (stale), the start time instead.
private struct Countdown: View {
    let card: LiveCard
    let stale: Bool

    var body: some View {
        if stale {
            Text(card.start, format: .dateTime.hour().minute())
                .accessibilityLabel(Text("Started \(card.start, format: .dateTime.hour().minute())"))
        } else {
            Text(card.start, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

private struct ActionLink: View {
    let card: LiveCard

    var body: some View {
        Link(destination: card.runURL) {
            Label(card.actionLabel, systemImage: card.symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(.white)
                .background(.indigo, in: .capsule)
        }
        .accessibilityLabel("\(card.actionLabel), \(card.title)")
    }
}
#endif

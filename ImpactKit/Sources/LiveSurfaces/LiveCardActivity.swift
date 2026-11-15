#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// A card's Live Activity (UX.md → System surfaces): the Now phase only. Its one button opens Impact, which runs
/// the primary action. The same layouts serve StandBy, the Watch Smart Stack, and CarPlay.
public struct LiveCardActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveCard.self) { context in
            LockScreenView(card: context.attributes, stale: context.isStale)
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
                Image(systemName: card.symbol).foregroundStyle(.indigo).accessibilityLabel(card.title)
            } compactTrailing: {
                // When the system slows updates it writes "8 minutes": shrink rather than truncate.
                Countdown(card: card, stale: context.isStale).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: card.symbol).foregroundStyle(.indigo).accessibilityLabel(card.title)
            }
            .keylineTint(.indigo)
        }
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

/// Minutes to the start, then minutes since it, drawn by the system so it moves without updates. Once the Now
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

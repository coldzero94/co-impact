#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// A card's Live Activity (UX.md → System surfaces): the Now phase only. Its one button opens Impact, which runs
/// the primary action. StandBy shows the Lock Screen layout; the Watch Smart Stack and CarPlay show the small one,
/// without the button (it does nothing in CarPlay, and the car is glance-only). During a focus session, the goal, a
/// ring filling with time, and the time left, without a button: End focus is in Impact.
public struct LiveCardActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveCard.self) { context in
            ActivityLayout(card: context.attributes, stale: context.isStale)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            let card = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if card.focusSince != nil {
                        TimeRing(card: card).frame(width: 36, height: 36)
                    } else {
                        Image(systemName: card.symbol).font(.title2).foregroundStyle(.indigo)
                            .accessibilityHidden(true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(card: card, stale: context.isStale).font(.title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(card.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Answer(card: card).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        ActionLink(card: card)
                    }
                }
            } compactLeading: {
                // With limited width, Apple's fallback: the leading view in a 28-pt circle (the ring) and an empty
                // trailing one, which the system hides.
                LimitedWidth { limited in
                    if limited || card.focusSince != nil {
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
private struct ActivityLayout: View {
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
                Answer(card: card).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
        } else {
            LockScreenView(card: card, stale: stale)
        }
    }
}

/// Time left to the start as a ring around the card's symbol, drawn by the system: small enough for the minimal
/// view and, with limited width, the 28-pt circle Apple asks for, where timer text would truncate (unverified on
/// screen: ARCHITECTURE.md → To verify). Empty from the start on. During a focus session, the ring fills with time
/// until the block's end, the Impact ring's shape (UX.md → The Impact moment).
private struct TimeRing: View {
    let card: LiveCard

    var body: some View {
        Group {
            if let since = card.focusSince {
                ProgressView(timerInterval: since...max(since, card.nowPhase.upperBound), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: card.symbol).font(.caption2.weight(.semibold))
                }
            } else {
                ProgressView(timerInterval: card.nowPhase.lowerBound...card.start, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: card.symbol).font(.caption2.weight(.semibold))
                }
            }
        }
        .progressViewStyle(.circular)
        .tint(.indigo)
        .foregroundStyle(.indigo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.focusSince == nil
            ? Text("\(card.title), \(card.start, format: .dateTime.hour().minute())")
            : Text("\(card.title), focusing until \(card.nowPhase.upperBound, format: .dateTime.hour().minute())"))
    }
}

/// The card's answer line; during a focus session, until when (short: on the Lock Screen it shares a line with the
/// time left).
private struct Answer: View {
    let card: LiveCard

    var body: some View {
        if card.focusSince != nil {
            Text("Until \(card.nowPhase.upperBound, format: .dateTime.hour().minute())")
        } else {
            Text(card.answer)
        }
    }
}

/// Whether the Dynamic Island draws compact and minimal views with limited width (iOS 27, e.g. in landscape, on
/// iPhone Duo, or with two or more activities on iPhone 18 Pro); never before iOS 27.
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
                if card.focusSince != nil {
                    TimeRing(card: card).frame(width: 28, height: 28)
                } else {
                    Image(systemName: card.symbol).font(.title3).foregroundStyle(.indigo)
                        .frame(width: 28).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.headline).lineLimit(1)
                    Answer(card: card).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
/// phase has passed (stale), the start time instead. During a focus session, the time left until the block's end.
private struct Countdown: View {
    let card: LiveCard
    let stale: Bool

    var body: some View {
        if let since = card.focusSince, !stale {
            Text(timerInterval: since...max(since, card.nowPhase.upperBound), countsDown: true)
                .monospacedDigit().multilineTextAlignment(.trailing)
        } else if stale {
            Text(card.start, format: .dateTime.hour().minute())
                .accessibilityLabel(Text("Started \(card.start, format: .dateTime.hour().minute())"))
        } else {
            Text(card.start, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

/// The primary action's button; none during a focus session, which Impact ends.
private struct ActionLink: View {
    let card: LiveCard

    var body: some View {
        if card.focusSince == nil {
            link
        }
    }

    private var link: some View {
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

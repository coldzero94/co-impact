#if os(iOS)
import AppIntents
import ImpactEngine
import SwiftUI
import WidgetKit

/// The Next up control (UX.md → System surfaces) for Control Center, the Lock Screen, and the Action button: a
/// fixed button, since a control's value is not refreshed while Impact does not run (ARCHITECTURE.md → Platform
/// facts), so a time on it would go stale. Pressing it opens Impact, which runs today's Next up's primary action.
public struct NextUpControl: ControlWidget {
    public static let kind = "NextUpControl"

    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RunNextUpIntent()) {
                Label("Next up", systemImage: "arrow.forward.circle")
                    .controlWidgetActionHint("Run next up")
            }
        }
        .displayName("Next up")
        .description("Joins today's next meeting or starts directions, through Impact.")
    }
}

/// The Next up control's action: brings Impact to the front, then leaves a run request for the card that runs now
/// (`NextCards.runnable`: today's Next up, or a meeting just after midnight once in its Soon phase), which live
/// Home runs as it runs a run link. With none, Impact just opens, so a meeting is never joined the evening before.
public struct RunNextUpIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Next Up"
    public static let description = IntentDescription("Opens Impact and runs today's next event's main action.")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    /// The control's action only: Siri and Shortcuts have the App Shortcuts (UX.md → System surfaces).
    public static let isDiscoverable = false

    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        if let (events, state, engine) = NextCards.read(now: now, calendar: calendar),
           let card = NextCards.runnable(in: NextCards.home(events: events, state: state, now: now, calendar: calendar,
                                                            engine: engine), now: now, calendar: calendar) {
            RunRequests.shared.pending = RunRequest(cardID: card.id)
        }
        return .result()
    }
}
#endif

#if os(iOS)
import AppIntents
import ImpactEngine
import SwiftUI
import WidgetKit

/// The Next up control (UX.md → System surfaces) for Control Center, the Lock Screen, and the Action button: the
/// card the widgets show, as its symbol and clock time (not a countdown: a control's value changes only when it is
/// reloaded or used). Pressing it opens Impact, which runs that card's primary action as its run link does.
public struct NextUpControl: ControlWidget {
    public static let kind = "NextUpControl"

    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetButton(action: RunNextUpIntent()) {
                Label(value.time, systemImage: value.symbol)
                    .controlWidgetActionHint(value.hint)
            }
        }
        .displayName("Next up")
        .description("Joins your next meeting or starts directions, through Impact.")
    }

    /// What the control shows: the card's symbol and time, and the Action button's hint for its primary action.
    struct Value: Sendable {
        let symbol: String
        let time: String
        let hint: String
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value { Value(symbol: "video.fill", time: "10:00 AM", hint: "Join meeting") }

        func currentValue() async throws -> Value { await Self.value(now: .now) }

        @MainActor static func value(now: Date) -> Value {
            let calendar = Calendar.autoupdatingCurrent
            guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else {
                return Value(symbol: "exclamationmark.triangle", time: "Can't read calendar", hint: "Open Impact")
            }
            guard let card = NextCards.moments(events: events, state: state, now: now, calendar: calendar,
                                               engine: engine).first?.card else {
                return Value(symbol: "checkmark", time: "Nothing today", hint: "Open Impact")
            }
            // As the widgets: another day's card names its day, so 8:00 tomorrow never reads as tonight.
            let time = calendar.isDate(card.start, inSameDayAs: now)
                ? card.start.formatted(.dateTime.hour().minute())
                : card.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return Value(symbol: card.symbol, time: time, hint: card.primaryAction?.kind.label ?? "Open Impact")
        }
    }
}

/// The Next up control's action: brings Impact to the front, then leaves a run request for the card the control
/// shows, which live Home runs as it runs a run link. With no card, Impact just opens.
public struct RunNextUpIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Next Up"
    public static let description = IntentDescription("Opens Impact and runs your next event's main action.")
    public static let supportedModes: IntentModes = .foreground(.immediate)

    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        if let (events, state, engine) = NextCards.read(now: now, calendar: calendar),
           let card = NextCards.moments(events: events, state: state, now: now, calendar: calendar,
                                        engine: engine).first?.card {
            RunRequests.shared.pending = RunRequest(cardID: card.id)
        }
        return .result()
    }
}
#endif

import AppIntents
import ImpactEngine
import LiveSurfaces

// App Shortcuts (UX.md → System surfaces). Their intents live in the app target: Apple supports localized phrases
// only for intents the main app declares (ARCHITECTURE.md → Platform facts). What they choose and run is
// LiveSurfaces' (`NextCards`, `RunRequests`); their phrases and answers are in AppShortcuts.xcstrings and
// Localizable.xcstrings, in English and Korean.

struct ImpactShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsNextIntent(),
                    phrases: ["What's next in \(.applicationName)", "What's my next event in \(.applicationName)"],
                    shortTitle: "What's Next", systemImageName: "calendar")
        AppShortcut(intent: JoinNextMeetingIntent(),
                    phrases: ["Join my next meeting in \(.applicationName)", "Join my next meeting with \(.applicationName)"],
                    shortTitle: "Join Next Meeting", systemImageName: "video.fill")
        AppShortcut(intent: DirectionsToNextIntent(),
                    phrases: ["Directions to my next appointment in \(.applicationName)",
                              "Get directions to my next appointment with \(.applicationName)"],
                    shortTitle: "Directions to Next", systemImageName: "car.fill")
    }
}

/// "What's next in Impact": says the next card as the widgets show it (Home's Next up, else the first card ahead),
/// without opening Impact. The answer is complete when spoken, with nothing on screen.
struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription("Says the next event that needs you, and when.")
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else {
            return .result(dialog: "Impact can't read your calendar.")
        }
        guard let card = NextCards.moments(events: events, state: state, now: now, calendar: calendar,
                                           engine: engine).first?.card else {
            return .result(dialog: "Nothing needs you today.")
        }
        let time = calendar.isDate(card.start, inSameDayAs: now)
            ? card.start.formatted(date: .omitted, time: .shortened)
            : card.start.formatted(.dateTime.weekday(.wide).hour().minute())
        return .result(dialog: "Next: \(card.title), \(time). \(card.keyFact).")
    }
}

/// "Join my next meeting in Impact": today's first meeting still to do with a link, joined through Impact.
struct JoinNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Next Meeting"
    static let description = IntentDescription("Opens Impact and joins your next meeting with a link today.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog = switch try await runNext(.join) {
        case .noCalendar: "Impact can't read your calendar."
        case .nothing: "No meeting with a link today."
        case .running(let title): "Joining \(title)."
        }
        return .result(dialog: dialog)
    }
}

/// "Directions to my next appointment in Impact": today's first in-person card still to do, routed through Impact.
struct DirectionsToNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Directions to Next Appointment"
    static let description = IntentDescription("Opens Impact and starts directions to your next appointment today.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog = switch try await runNext(.directions) {
        case .noCalendar: "Impact can't read your calendar."
        case .nothing: "No appointment with a place today."
        case .running(let title): "Directions to \(title)."
        }
        return .result(dialog: dialog)
    }
}

enum NextRun {
    case noCalendar, nothing, running(title: String)
}

extension AppIntent {
    /// Finds today's next card still to do with `action` (`NextCards.next`) and, if there is one, brings Impact to
    /// the front, where live Home runs it as it runs a run link. Without one, Impact stays in the background.
    @MainActor func runNext(_ action: RunAction) async throws -> NextRun {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else { return .noCalendar }
        let home = NextCards.home(events: events, state: state, now: now, calendar: calendar, engine: engine)
        guard let card = NextCards.next(action, in: home, state: state, now: now, calendar: calendar) else {
            return .nothing
        }
        try await continueInForeground(alwaysConfirm: false)
        RunRequests.shared.pending = RunRequest(cardID: card.id, action: action)
        return .running(title: card.title)
    }
}

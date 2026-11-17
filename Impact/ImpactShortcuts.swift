import AppIntents
import ImpactEngine
import LiveSurfaces

// App Shortcuts (UX.md → System surfaces). Their intents live in the app target: Apple supports localized phrases
// only for intents the main app declares (ARCHITECTURE.md → Platform facts). What they choose and run is
// LiveSurfaces' (`NextCards`, `RunRequests`). Phrases are in AppShortcuts.xcstrings; titles and answers in the
// Shortcuts table, in English and Korean. Not the default Localizable table: package views' `Text` looks up the
// main bundle's, so a shared key would turn that line of an English screen Korean.

/// A title or answer from the Shortcuts table.
private func shortcuts(_ value: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(value, table: "Shortcuts")
}

struct ImpactShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsNextIntent(),
                    phrases: ["What's next in \(.applicationName)", "What's my next event in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("What's Next", table: "Shortcuts"), systemImageName: "calendar")
        AppShortcut(intent: JoinNextMeetingIntent(),
                    phrases: ["Join my next meeting in \(.applicationName)", "Join my next meeting with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Join Next Meeting", table: "Shortcuts"), systemImageName: "video.fill")
        AppShortcut(intent: DirectionsToNextIntent(),
                    phrases: ["Directions to my next appointment in \(.applicationName)",
                              "Get directions to my next appointment with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Directions to Next", table: "Shortcuts"), systemImageName: "car.fill")
    }
}

/// "What's next in Impact": says the next card as the widgets show it (Home's Next up, else the first card ahead),
/// without opening Impact. The answer is complete when spoken, with nothing on screen.
struct WhatsNextIntent: AppIntent {
    static let title = LocalizedStringResource("What's Next", table: "Shortcuts")
    static let description = IntentDescription(LocalizedStringResource("Says the next event that needs you, and when.",
                                                                       table: "Shortcuts"))
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else {
            return .result(dialog: IntentDialog(shortcuts("Impact can't read your calendar.")))
        }
        guard let card = NextCards.moments(events: events, state: state, now: now, calendar: calendar,
                                           engine: engine).first?.card else {
            return .result(dialog: IntentDialog(shortcuts("Nothing needs you today.")))
        }
        let time = calendar.isDate(card.start, inSameDayAs: now)
            ? card.start.formatted(date: .omitted, time: .shortened)
            : card.start.formatted(.dateTime.weekday(.wide).hour().minute())
        return .result(dialog: IntentDialog(shortcuts("Next: \(card.title), \(time). \(card.keyFact).")))
    }
}

/// "Join my next meeting in Impact": today's first meeting still to do with a link, joined through Impact.
struct JoinNextMeetingIntent: AppIntent {
    static let title = LocalizedStringResource("Join Next Meeting", table: "Shortcuts")
    static let description = IntentDescription(LocalizedStringResource(
        "Opens Impact and joins your next meeting with a link today.", table: "Shortcuts"))
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = switch try await runNext(.join) {
        case .noCalendar: shortcuts("Impact can't read your calendar.")
        case .nothing: shortcuts("No meeting with a link today.")
        case .running(let title): shortcuts("Joining \(title).")
        }
        return .result(dialog: IntentDialog(answer))
    }
}

/// "Directions to my next appointment in Impact": today's first in-person card still to do, routed through Impact.
struct DirectionsToNextIntent: AppIntent {
    static let title = LocalizedStringResource("Directions to Next Appointment", table: "Shortcuts")
    static let description = IntentDescription(LocalizedStringResource(
        "Opens Impact and starts directions to your next appointment today.", table: "Shortcuts"))
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = switch try await runNext(.directions) {
        case .noCalendar: shortcuts("Impact can't read your calendar.")
        case .nothing: shortcuts("No appointment with a place today.")
        case .running(let title): shortcuts("Directions to \(title).")
        }
        return .result(dialog: IntentDialog(answer))
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

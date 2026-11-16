import Foundation
import ImpactEngine
import LiveSurfaces

/// Display text for a card (UX.md → Card anatomy).
extension ImpactCard {
    /// Details (UX.md → Card detail), from the facts `ImpactEngine.card(for:now:)` labels.
    var organizer: String? { facts.first { $0.label == "Organizer" }?.value }
    var attendees: [String] { facts.filter { $0.label == "Attendee" }.map(\.value) }
    var notes: String? { facts.first { $0.label == "Notes" }?.value }

    /// The answer to the card's question (P1).
    /// shortcut: in-person answers show the place; once routing exists they show the leave-by time,
    /// keeping the place when no route exists (PRODUCT.md → Card timeline).
    var answer: String {
        let link = "\(provider ?? "Meeting") link ready"
        return switch kind {
        case .onlineMeeting: link
        case .hybrid: place.map { "\(link) · \($0.title)" } ?? link
        case .inPerson: place.map { $0.address ?? $0.title } ?? ""
        }
    }
}

extension ActionKind {
    /// Replaces the label once the action is marked done (UX.md → Card anatomy).
    var doneLabel: String {
        switch self {
        case .joinMeeting: "Joined"
        case .directions: "Directions opened"
        case .openLink: "Link opened"
        case .call: "Call opened"
        }
    }

    /// The failure alert's title: what did not open.
    var failureTitle: String {
        switch self {
        case .joinMeeting: "The meeting link didn't open"
        case .directions: "Maps didn't open"
        case .openLink(let url): "\(url.shortHost ?? "The link") didn't open"
        case .call: "The call didn't start"
        }
    }
}


/// Next up's large time (UX.md → Home): minutes under an hour, the clock time from an hour out, Now from the start.
enum Countdown: Equatable {
    case now
    case minutes(Int)
    case clock

    init(to start: Date, now: Date) {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        self = minutes <= 0 ? .now : minutes < 60 ? .minutes(minutes) : .clock
    }
}

/// "3 of 4 events need you" (UX.md → Home → Summary line).
func summaryLine(cards: Int, eventsLeft: Int) -> String {
    guard eventsLeft > 0 else { return "No events left today" }
    return "\(cards) of \(eventsLeft) \(eventsLeft == 1 ? "event" : "events") \(cards == 1 ? "needs" : "need") you"
}

/// "Mina, Joon, and Sara", or with more than three people "Mina, Joon, and 4 others". English, like the rest of
/// the app's text, whatever the region. A guest the calendar names neither by name nor address is an unnamed guest,
/// listed after the named ones so they keep the visible places.
func attendeeLine(_ names: [String]) -> String {
    let names = names.filter { !$0.isEmpty } + names.filter(\.isEmpty).map { _ in "Unnamed guest" }
    let list = ListFormatStyle<StringStyle, [String]>.list(type: .and).locale(Locale(identifier: "en_US"))
    guard names.count > 3 else { return names.formatted(list) }
    return (names.prefix(2) + ["\(names.count - 2) others"]).formatted(list)
}

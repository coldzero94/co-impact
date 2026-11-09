import Foundation
import ImpactEngine

/// Display text for a card (UX.md → Card anatomy). It reads the card's actions; the engine creates
/// only calendar or computed ones, so inferred actions must never feed this text (hard rule 2).
extension ImpactCard {
    var meetingURL: URL? {
        actions.lazy.compactMap { if case .joinMeeting(let url) = $0.kind { url } else { nil } }.first
    }

    var place: Place? {
        actions.lazy.compactMap { if case .directions(let place) = $0.kind { place } else { nil } }.first
    }

    var provider: String? { meetingURL.flatMap(ImpactEngine.meetingProvider) }

    /// The answer to the card's question (P1).
    /// shortcut: in-person answers and row facts show the place until routing exists; then the leave-by time (UX.md → Home, Card detail).
    var answer: String {
        let link = "\(provider ?? "Meeting") link ready"
        return switch kind {
        case .onlineMeeting: link
        case .hybrid: place.map { "\(link) · \($0.title)" } ?? link
        case .inPerson: place.map { $0.address ?? $0.title } ?? ""
        }
    }

    /// The one key fact on a row and on Next up's top line.
    var keyFact: String {
        switch kind {
        case .onlineMeeting, .hybrid: provider ?? "Online"
        case .inPerson: place?.title ?? ""
        }
    }

    var symbol: String {
        switch kind {
        case .onlineMeeting, .hybrid: "video.fill"
        case .inPerson: "car.fill"
        }
    }
}

extension ActionKind {
    var label: String {
        switch self {
        case .joinMeeting: "Join meeting"
        case .directions: "Directions"
        case .openLink: "Open link"
        case .call: "Call"
        }
    }

    var symbol: String {
        switch self {
        case .joinMeeting: "video.fill"
        case .directions: "car.fill"
        case .openLink: "link"
        case .call: "phone.fill"
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

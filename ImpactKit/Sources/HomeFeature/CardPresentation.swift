import Foundation
import ImpactEngine

/// Display text for a card, from its confirmed or computed actions only (UX.md → Card anatomy).
extension ImpactCard {
    var meetingURL: URL? {
        actions.lazy.compactMap { if case .joinMeeting(let url) = $0.kind { url } else { nil } }.first
    }

    var place: Place? {
        actions.lazy.compactMap { if case .directions(let place) = $0.kind { place } else { nil } }.first
    }

    /// The provider name for a meeting link; the hosts are those of PRODUCT.md → Signals.
    var provider: String? {
        guard let host = meetingURL?.host?.lowercased() else { return nil }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return "Zoom" }
        if host.hasSuffix(".webex.com") { return "Webex" }
        return switch host {
        case "meet.google.com": "Google Meet"
        case "teams.microsoft.com", "teams.live.com": "Teams"
        case "facetime.apple.com": "FaceTime"
        default: nil
        }
    }

    /// The answer to the card's question (P1).
    var answer: String {
        let link = "\(provider ?? "Meeting") link ready"
        return switch kind {
        case .onlineMeeting: link
        case .hybrid: place.map { "\(link) · \($0.title)" } ?? link
        case .inPerson: place.map { $0.address ?? $0.title } ?? ""
        }
    }

    /// The one key fact on a departure-board row.
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

/// Next up's large time: relative under an hour, otherwise the clock time (UX.md → Card anatomy).
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

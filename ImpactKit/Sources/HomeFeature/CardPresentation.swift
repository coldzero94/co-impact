import Foundation
import ImpactEngine

/// Display text for a card (UX.md → Card anatomy).
extension ImpactCard {
    var meetingURL: URL? {
        confirmedActions.lazy.compactMap { if case .joinMeeting(let url) = $0.kind { url } else { nil } }.first
    }

    var place: Place? {
        confirmedActions.lazy.compactMap { if case .directions(let place) = $0.kind { place } else { nil } }.first
    }

    var provider: String? { meetingURL.flatMap(ImpactEngine.meetingProvider) }

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

    /// The one key fact on a row and on Next up's top line.
    /// shortcut: in-person cards show the place; with routing they show the leave-by time, keeping the place
    /// when no route exists (PRODUCT.md → Card timeline).
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
        case .openLink(let url): url.shortHost.map { "Open \($0)" } ?? "Open link"
        case .call: "Call"
        }
    }

    /// Replaces the label once the action ran (UX.md → Card anatomy).
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

    var symbol: String {
        switch self {
        case .joinMeeting: "video.fill"
        case .directions: "car.fill"
        case .openLink: "link"
        case .call: "phone.fill"
        }
    }
}

extension URL {
    /// The host to label a link by (PRODUCT.md → Action catalog): lowercased, as browsers show it, so "paypaI"
    /// cannot pass for "paypal", and without a leading "www.". Links come from notes other people write, so
    /// anything but a plain ASCII host name (a lookalike script, percent-encoding, control characters) gives
    /// nil and the generic label.
    var shortHost: String? {
        guard let host = host()?.lowercased().replacing(/^www\./, with: ""), !host.isEmpty,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
        else { return nil }
        return host
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

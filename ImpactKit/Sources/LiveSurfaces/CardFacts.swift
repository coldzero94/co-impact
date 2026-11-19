import Foundation
import ImpactEngine

/// What every surface shows of a card besides its title (UX.md → Card anatomy), shared by Home, the Live Activity,
/// and the widgets.
extension ImpactCard {
    public var meetingURL: URL? {
        confirmedActions.lazy.compactMap { if case .joinMeeting(let url) = $0.kind { url } else { nil } }.first
    }

    public var place: Place? {
        confirmedActions.lazy.compactMap { if case .directions(let place) = $0.kind { place } else { nil } }.first
    }

    public var provider: String? { meetingURL.flatMap(ImpactEngine.meetingProvider) }

    /// The one key fact on a row, on Next up's top line, and on the widgets.
    /// shortcut: in-person cards show the place; with routing they show the leave-by time, keeping the place
    /// when no route exists (PRODUCT.md → Card timeline).
    public var keyFact: String {
        switch kind {
        case .onlineMeeting, .hybrid: provider ?? "Online"
        case .inPerson: place?.title ?? ""
        case .focusBlock: "Focus"
        }
    }

    public var symbol: String {
        switch kind {
        case .onlineMeeting, .hybrid: "video.fill"
        case .inPerson: "car.fill"
        case .focusBlock: "timer"
        }
    }
}

extension ActionKind {
    public var label: String {
        switch self {
        case .joinMeeting: "Join meeting"
        case .directions: "Directions"
        case .openLink(let url): url.shortHost.map { "Open \($0)" } ?? "Open link"
        case .call: "Call"
        case .startFocus: "Start focus"
        }
    }

    public var symbol: String {
        switch self {
        case .joinMeeting: "video.fill"
        case .directions: "car.fill"
        case .openLink: "link"
        case .call: "phone.fill"
        case .startFocus: "timer"
        }
    }
}

extension URL {
    /// The host to label a link by (PRODUCT.md → Action catalog): lowercased, as browsers show it, so "paypaI"
    /// cannot pass for "paypal", and without a leading "www.". Links come from notes other people write, so
    /// anything but a plain ASCII host name (a lookalike script, percent-encoding, control characters) gives
    /// nil and the generic label.
    public var shortHost: String? {
        guard let host = host()?.lowercased().replacing(/^www\./, with: ""), !host.isEmpty,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
        else { return nil }
        return host
    }
}

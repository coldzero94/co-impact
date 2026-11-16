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

    /// The one key fact on a row, on Next up's top line, and on the Lock Screen widget.
    /// shortcut: in-person cards show the place; with routing they show the leave-by time, keeping the place
    /// when no route exists (PRODUCT.md → Card timeline).
    public var keyFact: String {
        switch kind {
        case .onlineMeeting, .hybrid: provider ?? "Online"
        case .inPerson: place?.title ?? ""
        }
    }

    public var symbol: String {
        switch kind {
        case .onlineMeeting, .hybrid: "video.fill"
        case .inPerson: "car.fill"
        }
    }
}

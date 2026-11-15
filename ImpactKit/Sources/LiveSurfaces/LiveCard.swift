import Foundation

/// What a card's Live Activity shows (UX.md → System surfaces). It is fixed when the activity is scheduled:
/// nothing can update it without a server (ARCHITECTURE.md → Refresh and platform constraints), so a card that
/// changes gets a new activity instead.
public struct LiveCard: Codable, Hashable, Sendable {
    public var cardID: String
    public var title: String
    /// The card's answer line, e.g. "Zoom link ready".
    public var answer: String
    /// The primary action's SF Symbol and label.
    public var symbol: String
    public var actionLabel: String
    /// The event's start, which the countdown counts to.
    public var start: Date
    /// When the activity starts and goes stale (`ImpactEngine.nowPhase`).
    public var nowPhase: Range<Date>

    public init(cardID: String, title: String, answer: String, symbol: String, actionLabel: String, start: Date,
                nowPhase: Range<Date>) {
        self.cardID = cardID
        self.title = title
        self.answer = answer
        self.symbol = symbol
        self.actionLabel = actionLabel
        self.start = start
        self.nowPhase = nowPhase
    }

    /// The link the activity's action button opens: Impact, which runs the card's primary action. No system
    /// surface can open a meeting, Maps, or a call directly (research/system-surfaces.md).
    public var runURL: URL { Self.runURL(cardID: cardID) }

    public static func runURL(cardID: String) -> URL {
        var components = URLComponents()
        components.scheme = "impact"
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "card", value: cardID)]
        guard let url = components.url else { preconditionFailure("No run URL for card \(cardID)") }
        return url
    }

    /// The card a run URL names, or nil for any other URL.
    public static func cardID(fromRunURL url: URL) -> String? {
        guard url.scheme == "impact", url.host() == "run",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "card" })?.value,
              !id.isEmpty else { return nil }
        return id
    }
}

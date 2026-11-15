import Foundation

/// What a card's Live Activity shows (UX.md → System surfaces). It is the activity's `ActivityAttributes`, which
/// cannot change once requested, and Impact sends no updates (nothing could schedule one while Impact does not
/// run), so a card that changes gets a new activity: `LiveActivities.sync` tells activities apart by equality.
/// The system stores it with each pending or running activity, across app updates: renaming or adding a
/// non-optional property can leave old activities that no longer decode, which sync then cannot end or match.
public struct LiveCard: Codable, Hashable, Sendable {
    public let cardID: String
    public let title: String
    /// The card's answer line, e.g. "Zoom link ready".
    public let answer: String
    /// The primary action's SF Symbol.
    public let symbol: String
    /// The primary action's label, e.g. "Join meeting".
    public let actionLabel: String
    /// The event's start, which the countdown counts to.
    public let start: Date
    /// When the activity starts and goes stale (`ImpactEngine.nowPhase`); it holds `start`.
    public let nowPhase: Range<Date>

    public init(cardID: String, title: String, answer: String, symbol: String, actionLabel: String, start: Date,
                nowPhase: Range<Date>) {
        assert(nowPhase.lowerBound <= start && start <= nowPhase.upperBound, "Now phase \(nowPhase) misses \(start)")
        self.cardID = cardID
        self.title = title
        self.answer = answer
        self.symbol = symbol
        self.actionLabel = actionLabel
        self.start = start
        self.nowPhase = nowPhase
    }

    /// The link the activity's action button opens: Impact, which runs the card's primary action. Apple documents
    /// no way for a system surface to open a meeting, Maps, or a call directly (research/system-surfaces.md).
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

    /// Which wanted cards a sync requests (`LiveActivities.sync`): those without an activity yet, started at once
    /// if already in their Now phase (no alert: Impact is in front), else scheduled for its start (with its alert).
    public static func toRequest(wanted: [LiveCard], existing: Set<LiveCard>, now: Date)
        -> (startNow: [LiveCard], schedule: [LiveCard]) {
        let missing = wanted.filter { !existing.contains($0) }
        return (missing.filter { now >= $0.nowPhase.lowerBound }, missing.filter { now < $0.nowPhase.lowerBound })
    }
}

import Foundation
import ImpactEngine

/// What a card's Live Activity shows (UX.md → System surfaces). It is the activity's `ActivityAttributes`, which
/// cannot change once requested, and Impact sends no updates (nothing could schedule one while Impact does not
/// run), so a card that changes gets a new activity: `LiveActivities.sync` tells activities apart by equality.
/// The system keeps it with each pending or running activity across launches (ARCHITECTURE.md → Platform facts):
/// renaming or adding a non-optional property could leave stored activities that no longer decode, which sync then
/// cannot end or match.
/// shortcut: the form still changes between builds (e.g. `runToken`), relying on installing a new build ending the
/// stored activities (seen in the simulator, unverified on a device, step 10); decode new properties with defaults
/// once Impact is released.
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
    /// The secret its run link carries, so only Impact's own activities can run a card's action.
    public let runToken: String
    /// Whether its fallback alert (`NowAlerts`) is Time Sensitive: a meeting's start and leave-by are, a focus
    /// block's start is not (PRODUCT.md → Interruptions).
    public let timeSensitive: Bool
    /// The focus session on this focus block, while one runs: the activity then shows the session, its ring filling
    /// with time until the session's end, the block's end when focus started (UX.md → The Impact moment).
    public let focus: FocusSession?

    public init(cardID: String, title: String, answer: String, symbol: String, actionLabel: String, start: Date,
                nowPhase: Range<Date>, runToken: String, timeSensitive: Bool, focus: FocusSession? = nil) {
        assert(nowPhase.lowerBound <= start && start <= nowPhase.upperBound, "Now phase \(nowPhase) misses \(start)")
        self.cardID = cardID
        self.title = title
        self.answer = answer
        self.symbol = symbol
        self.actionLabel = actionLabel
        self.start = start
        self.nowPhase = nowPhase
        self.runToken = runToken
        self.timeSensitive = timeSensitive
        self.focus = focus
    }

    /// The link the activity's action button opens: Impact, which runs the card's primary action. Apple documents
    /// no way for a system surface to open a meeting, Maps, or a call directly (research/system-surfaces.md).
    public var runURL: URL { Self.runURL(cardID: cardID, token: runToken) }

    public static func runURL(cardID: String, token: String) -> URL {
        var components = URLComponents()
        components.scheme = "impact"
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "card", value: cardID), URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { preconditionFailure("No run URL for card \(cardID)") }
        return url
    }

    /// Whether the URL is a run link at all, with or without the right token.
    public static func isRunURL(_ url: URL) -> Bool { url.scheme == "impact" && url.host() == "run" }

    /// The card a run URL names when it carries `token`; nil for any other URL or token.
    public static func cardID(fromRunURL url: URL, token: String) -> String? {
        guard isRunURL(url), !token.isEmpty,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "token" })?.value == token,
              let id = items.first(where: { $0.name == "card" })?.value, !id.isEmpty else { return nil }
        return id
    }

    /// The wanted cards without an activity yet (`LiveActivities.sync`): `startNow`, already in their Now phase or
    /// showing a focus session (which can start in the Soon phase), which Impact in front starts at once without an
    /// alert; `schedule`, the rest, scheduled for their Now phase with its alert, or given the fallback alert where that
    /// cannot be.
    public static func toRequest(wanted: [LiveCard], existing: Set<LiveCard>, now: Date)
        -> (startNow: [LiveCard], schedule: [LiveCard]) {
        let missing = wanted.filter { !existing.contains($0) }
        let atOnce = { (card: LiveCard) in now >= card.nowPhase.lowerBound || card.focus != nil }
        return (missing.filter(atOnce), missing.filter { !atOnce($0) })
    }
}

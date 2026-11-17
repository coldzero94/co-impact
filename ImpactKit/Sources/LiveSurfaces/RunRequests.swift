import Foundation
import ImpactEngine
import Observation

/// An action an App Intent asks Impact to run on a card.
public enum RunAction: Sendable, Hashable {
    case join, directions

    public func matches(_ kind: ActionKind) -> Bool {
        switch (self, kind) {
        case (.join, .joinMeeting), (.directions, .directions): true
        default: false
        }
    }
}

/// A card's action for live Home to run: the primary one for a run link (`LiveCard.runURL`), or the one an App
/// Intent asked for.
public struct RunRequest: Sendable, Hashable {
    public let cardID: String
    public let action: RunAction?

    public init(cardID: String, action: RunAction? = nil) {
        self.cardID = cardID
        self.action = action
    }

    /// The confirmed action to run on `card`, or nil when it has none of the kind asked for.
    public func pick(from card: ImpactCard) -> ImpactAction? {
        guard let action else { return card.primaryAction }
        return card.confirmedActions.first { action.matches($0.kind) }
    }
}

/// Where Impact's App Intents leave a request for live Home, inside Impact's process, once Impact is in front.
@MainActor @Observable public final class RunRequests {
    public static let shared = RunRequests()
    public var pending: RunRequest?
}

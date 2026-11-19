import Foundation

/// A focus session (PRODUCT.md → Focus blocks): the focus block's card ID, when Start focus ran, and the block's end,
/// where the session ends at the latest (`ActionLog.recordFocus`).
public struct FocusSession: Sendable, Hashable, Codable {
    public let cardID: String
    public let start: Date
    public let end: Date

    /// Start focus on `card` at `now`: nil unless the card is a focus block in its Soon or Now phase, from 15 minutes
    /// before its start until its end.
    public init?(card: ImpactCard, now: Date) {
        guard card.kind == .focusBlock, ImpactEngine.isSoonOrNow(card, now: now) else { return nil }
        cardID = card.id
        start = now
        end = card.end
    }
}

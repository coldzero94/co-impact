import Foundation

/// A focus session (PRODUCT.md → Focus blocks): the focus block's card ID and goal, when Start focus ran, and the
/// block's end, where the session ends at the latest (`ActionLog.recordFocus`).
public struct FocusSession: Sendable, Hashable, Codable {
    public let cardID: String
    /// The goal, as the block's card showed it, for the daily log once the block may be gone.
    public let title: String
    public let start: Date
    public let end: Date

    /// Start focus on `card` at `now`: nil unless the card is a focus block in its Soon or Now phase, from 15 minutes
    /// before its start until its end. The start is cut to the second, so the session compares equal after any
    /// encoding (the Live Activity that shows it, `SurfaceState`).
    public init?(card: ImpactCard, now: Date) {
        guard card.kind == .focusBlock, ImpactEngine.isSoonOrNow(card, now: now) else { return nil }
        cardID = card.id
        title = card.title
        start = Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
        end = card.end
    }

    /// Whether the session still runs at `now` with `home` as Home shows it: before its end, with its block in its
    /// Soon or Now phase (not ended, moved, deleted, or dismissed).
    public func runs(in home: HomeSnapshot, now: Date) -> Bool {
        now < end && home.cards.contains { $0.id == cardID && ImpactEngine.isSoonOrNow($0, now: now) }
    }
}

extension ImpactCard {
    /// Whether Home and the widgets offer `action` now: Start focus from the block's Soon phase until it ends
    /// (`FocusSession`), every other action always.
    public func offers(_ action: ImpactAction, now: Date) -> Bool {
        action.kind != .startFocus || ImpactEngine.isSoonOrNow(self, now: now)
    }
}

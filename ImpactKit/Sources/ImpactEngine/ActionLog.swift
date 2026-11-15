import Foundation

/// The actions the user ran and the Impacts they recorded (PRODUCT.md → Completion semantics and Impact).
/// shortcut: only `impacts` is stored across launches (ARCHITECTURE.md → Storage), so after a relaunch only
/// a card's primary action shows as done (from its Impact); store the rest if card detail should keep them.
public struct ActionLog: Sendable {
    /// When each card's Impact was recorded, by card ID: at most one per card.
    public private(set) var impacts: [String: Date] = [:]
    private var done: [String: Set<ActionKind>] = [:]

    public init() {}

    /// Restores stored Impacts; their cards count as done.
    public init(impacts: [String: Date]) {
        self.impacts = impacts
    }

    /// Merges in Impacts read later; for a card in both, the earlier stamp wins.
    public mutating func restore(_ stored: [String: Date]) {
        impacts.merge(stored) { recorded, stored in min(recorded, stored) }
    }

    /// Marks `action` done on `card`. The card's `primaryAction` also records the card's Impact, once.
    /// Returns true when this call recorded the Impact. A primary action before the card's Soon phase is
    /// preparation, not doing it (PRODUCT.md → Completion semantics): it records nothing, so the card keeps Next
    /// up and its Now alert. An action passed with the wrong card records nothing in release builds instead of
    /// crashing (debug builds assert).
    @discardableResult
    public mutating func record(_ action: ImpactAction, on card: ImpactCard, at date: Date) -> Bool {
        guard card.actions.contains(action) else {
            assertionFailure("\(action.kind) is not an action of card \(card.id)")
            return false
        }
        let primary = action == card.primaryAction
        if primary, date < Self.countsFrom(card) { return false }
        done[card.id, default: []].insert(action.kind)
        guard primary, impacts[card.id] == nil else { return false }
        impacts[card.id] = date
        return true
    }

    /// When a card's primary action starts to count: its Soon phase. In person that starts 30 minutes before
    /// leave-by, which needs routing, so until then a trip of up to 90 minutes counts: from 2 hours before the start.
    /// shortcut: use leave-by − 30 minutes (PRODUCT.md → Card timeline) once routing gives leave-by.
    static func countsFrom(_ card: ImpactCard) -> Date {
        card.kind == .inPerson ? card.start.addingTimeInterval(-2 * 3_600) : ImpactEngine.soonStart(of: card)
    }

    /// Whether `action` was marked done on `card` (a primary action only once it counts); a primary action also counts as done when the card's Impact was
    /// restored from storage.
    public func isDone(_ action: ImpactAction, on card: ImpactCard) -> Bool {
        (done[card.id]?.contains(action.kind) ?? false) || (action == card.primaryAction && impacts[card.id] != nil)
    }

    /// Cards whose primary action counted, on any day: `home(completedCardIDs:)`.
    public var completedCardIDs: Set<String> { Set(impacts.keys) }

    /// Impacts recorded on the calendar day of `day`: `home(impactsToday:)`.
    public func impactCount(on day: Date, calendar: Calendar) -> Int {
        impacts.values.count { calendar.isDate($0, inSameDayAs: day) }
    }
}

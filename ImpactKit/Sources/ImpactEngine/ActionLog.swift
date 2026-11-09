import Foundation

/// The actions the user ran and the Impacts they recorded (PRODUCT.md → Completion semantics and Impact).
/// shortcut: memory only, so a relaunch forgets it; persist it (ARCHITECTURE.md → Storage) with real events in step 7.
public struct ActionLog: Sendable {
    /// When each card's Impact was recorded, by card ID: at most one per card.
    public private(set) var impacts: [String: Date] = [:]
    private var done: [String: Set<ActionKind>] = [:]

    public init() {}

    /// Marks `action` done on `card`. The card's primary action also records the card's Impact, once.
    /// Returns true when this call recorded the Impact.
    @discardableResult
    public mutating func record(_ action: ImpactAction, on card: ImpactCard, at date: Date) -> Bool {
        precondition(card.actions.contains(action), "\(action.kind) is not an action of card \(card.id)")
        done[card.id, default: []].insert(action.kind)
        guard action == card.actions.first, impacts[card.id] == nil else { return false }
        impacts[card.id] = date
        return true
    }

    public func isDone(_ action: ImpactAction, on card: ImpactCard) -> Bool {
        done[card.id]?.contains(action.kind) ?? false
    }

    /// Cards whose primary action ran, on any day: `home(completedCardIDs:)`.
    public var completedCardIDs: Set<String> { Set(impacts.keys) }

    /// Impacts recorded on the calendar day of `day`: `home(impactsToday:)`.
    public func impactCount(on day: Date, calendar: Calendar) -> Int {
        impacts.values.count { calendar.isDate($0, inSameDayAs: day) }
    }
}

import Foundation

/// What the user dismissed (UX.md → Dismissing; PRODUCT.md D6): single occurrences ("Not needed") and kinds of
/// event ("Don't suggest for events like this"). Its `rules` go to `home(suppressionRules:)`.
public struct Dismissals: Sendable, Hashable, Codable {
    /// Occurrence IDs the user marked not needed, with when each event ends; `pruned` drops ended ones.
    public private(set) var occurrences: [String: Date] = [:]
    /// Muted series and titles.
    /// shortcut: kept for good, with no way to unmute until Settings exist.
    public private(set) var muted: Set<SuppressionRule> = []

    public init() {}

    public var rules: [SuppressionRule] { occurrences.keys.map { .occurrence(id: $0) } + muted }

    /// "Not needed": hides this occurrence only, until it ends.
    public mutating func dismiss(_ event: CalendarEvent) {
        occurrences[event.id] = event.end
    }

    /// "Don't suggest for events like this": the recurring series, or else the same title on the same calendar.
    /// shortcut: a series mute keys on the device's item ID, so a moved occurrence (its own ID) still shows and a
    /// full sync can bring the series back (ARCHITECTURE.md → Platform facts); switch to
    /// `calendarItemExternalIdentifier` once its format is checked per server on a device.
    public mutating func mute(like event: CalendarEvent) {
        muted.insert(event.seriesID.map { .series(calendarID: event.calendarID, seriesID: $0) }
                     ?? .title(calendarID: event.calendarID, title: event.title))
    }

    /// Without dismissals of occurrences that have ended: no card can come back for them.
    public func pruned(now: Date) -> Dismissals {
        var kept = self
        kept.occurrences = occurrences.filter { $0.value > now }
        return kept
    }
}

import Foundation

/// What the user dismissed (UX.md → Dismissing; PRODUCT.md D6): single occurrences ("Not needed") and kinds of
/// event ("Don't suggest for events like this"). Its `rules` go to `home(suppressionRules:)`.
public struct Dismissals: Sendable, Hashable, Codable {
    /// Occurrence IDs the user marked not needed, with when; `pruned` drops old ones.
    public private(set) var occurrences: [String: Date] = [:]
    /// Muted series and titles.
    /// shortcut: kept for good, with no way to unmute until Settings exist.
    public private(set) var muted: Set<SuppressionRule> = []

    public init() {}

    public var rules: [SuppressionRule] { occurrences.keys.map { .occurrence(id: $0) } + muted }

    /// "Not needed": hides this occurrence only.
    public mutating func dismiss(_ event: CalendarEvent, at date: Date) {
        occurrences[event.id] = date
    }

    /// "Don't suggest for events like this": the recurring series, or else the same title on the same calendar.
    public mutating func mute(like event: CalendarEvent) {
        muted.insert(event.seriesID.map { .series(calendarID: event.calendarID, seriesID: $0) }
                     ?? .title(calendarID: event.calendarID, title: event.title))
    }

    /// Without occurrence dismissals older than two days: Home lists nothing that far back (PRODUCT.md → Horizon).
    public func pruned(now: Date) -> Dismissals {
        var kept = self
        kept.occurrences = occurrences.filter { now.timeIntervalSince($0.value) < 2 * 86_400 }
        return kept
    }
}

import Foundation

/// What the user dismissed (UX.md → Dismissing; PRODUCT.md D6): single occurrences ("Not needed") and kinds of
/// event ("Don't suggest for events like this"). Its `rules` go to `home(suppressionRules:)`.
public struct Dismissals: Sendable, Hashable, Codable {
    /// Occurrence IDs the user marked not needed, with when the dismissal lapses; `pruned` drops lapsed ones.
    public private(set) var occurrences: [String: Date] = [:]
    /// Muted series and titles.
    /// shortcut: kept for good, with no way to unmute until Settings exist.
    public private(set) var muted: Set<SuppressionRule> = []

    public init() {}

    public var rules: [SuppressionRule] { occurrences.keys.map { .occurrence(id: $0) } + muted }

    /// "Not needed": hides this occurrence only, until it ends but for at least two days, so an event moved later
    /// (same ID) stays hidden whether or not the app was relaunched; Home lists nothing beyond tomorrow noon.
    public mutating func dismiss(_ event: CalendarEvent, at date: Date) {
        occurrences[event.id] = max(event.end, date.addingTimeInterval(2 * 86_400))
    }

    /// "Don't suggest for events like this": the recurring series, or else the same title on the same calendar.
    /// shortcut: a series mute keys on the device's item ID, so a moved occurrence (its own ID) still shows and a
    /// full sync can bring the series back (ARCHITECTURE.md → Platform facts); switch to
    /// `calendarItemExternalIdentifier` once its format is checked per server on a device.
    public mutating func mute(like event: CalendarEvent) {
        muted.insert(event.seriesID.map { .series(calendarID: event.calendarID, seriesID: $0) }
                     ?? .title(calendarID: event.calendarID, title: event.title))
    }

    /// Without lapsed dismissals.
    public func pruned(now: Date) -> Dismissals {
        var kept = self
        kept.occurrences = occurrences.filter { $0.value > now }
        return kept
    }
}

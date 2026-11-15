import Foundation

/// What the user dismissed (UX.md → Dismissing; PRODUCT.md D6): single occurrences ("Not needed") and kinds of
/// event ("Don't suggest for events like this"). Its `rules` go to `home(suppressionRules:)`.
/// Stored as its synthesized `Codable` (and `SuppressionRule`'s): renaming a property, case, or label, or adding
/// a non-optional property, breaks loading stored data; `DismissalsTests.storedFormat` pins it.
public struct Dismissals: Sendable, Hashable, Codable {
    /// Occurrence IDs the user marked not needed, with when the dismissal lapses; `pruned` drops lapsed ones.
    public private(set) var occurrences: [String: Date] = [:]
    /// Muted series and titles.
    /// shortcut: kept for good, with no way to unmute until Settings exist.
    public private(set) var muted: Set<SuppressionRule> = []

    public init() {}

    public var rules: [SuppressionRule] { occurrences.keys.map { .occurrence(id: $0) } + muted }

    /// "Not needed": hides this occurrence only, until the later of its end and two days after the dismissal.
    /// Home lists nothing past tomorrow noon, so the occurrence stays hidden if it keeps its ID and is moved
    /// within that time; a move further out brings it back once the dismissal lapses. Callers prune on every
    /// rebuild, so a running app behaves as after a relaunch.
    public mutating func dismiss(_ event: CalendarEvent, at date: Date) {
        occurrences[event.id] = max(event.end, date.addingTimeInterval(2 * 86_400))
    }

    /// "Don't suggest for events like this": the recurring series, or else the same title on the same calendar.
    /// An untitled one-off has nothing that marks events like it, so it is only dismissed, not muted.
    /// shortcut: a series mute keys on the device's item ID, so a moved occurrence (its own ID) still shows and a
    /// full sync can bring the series back (ARCHITECTURE.md → Platform facts); switch to
    /// `calendarItemExternalIdentifier` once its format is checked per server on a device.
    public mutating func mute(like event: CalendarEvent, at date: Date) {
        if let series = event.seriesID {
            muted.insert(.series(calendarID: event.calendarID, seriesID: series))
        } else if !event.title.isEmpty {
            muted.insert(.title(calendarID: event.calendarID, title: event.title))
        } else {
            dismiss(event, at: date)
        }
    }

    /// Without lapsed dismissals.
    public func pruned(now: Date) -> Dismissals {
        var kept = self
        kept.occurrences = occurrences.filter { $0.value > now }
        return kept
    }
}

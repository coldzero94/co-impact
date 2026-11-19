import Foundation

/// The daily log (PRODUCT.md → Daily log): each Impact as it was recorded, and the user's one line per day. Stored as
/// its synthesized `Codable` (ARCHITECTURE.md → Storage): renaming a property or case, or adding a non-optional
/// property, sets the stored log aside; `LiveDataTests.dailyLogStore` pins the format.
public struct DailyLog: Sendable, Hashable, Codable {
    /// One Impact: what the user did, on what, and when it was recorded.
    public struct Entry: Sendable, Hashable, Codable {
        public enum Kind: Sendable, Hashable, Codable {
            /// Join meeting, from the card's Soon phase on.
            case joined
            /// Directions, from the card's Soon phase on: the user left.
            case left
            /// A focus session of 10 minutes or more, its length rounded to the minute.
            case focused(minutes: Int)
        }

        public let cardID: String
        public let kind: Kind
        /// The event's title, or a focus block's goal, as its card showed it.
        public let title: String
        public let date: Date
        /// The day it belongs to (`DailyLog.key`), fixed where it was recorded, so travel moves it to no other day.
        public let day: String

        /// An entry recorded at `date`, on its day in `calendar`.
        public init(cardID: String, kind: Kind, title: String, date: Date, calendar: Calendar) {
            self.cardID = cardID
            self.kind = kind
            self.title = title
            self.date = date
            day = DailyLog.key(for: date, calendar: calendar)
        }

        /// The entry for the Impact `card`'s primary action recorded at `date` (`ActionLog.record`); nil for a focus
        /// block, whose Impact comes from its session (`init(session:endedAt:calendar:)`).
        public init?(impactOf card: ImpactCard, at date: Date, calendar: Calendar) {
            let kind: Kind
            switch card.primaryAction?.kind {
            case .joinMeeting: kind = .joined
            case .directions: kind = .left
            default: return nil
            }
            self.init(cardID: card.id, kind: kind, title: card.title, date: date, calendar: calendar)
        }

        /// The entry for a focus session that recorded its block's Impact (`ActionLog.recordFocus`): stamped, as the
        /// Impact is, when it ended, at its end at the latest.
        public init(session: FocusSession, endedAt date: Date, calendar: Calendar) {
            let end = min(date, session.end)
            self.init(cardID: session.cardID, kind: .focused(minutes: Int((end.timeIntervalSince(session.start) / 60).rounded())),
                      title: session.title, date: end, calendar: calendar)
        }
    }

    /// A day of the log: its key (`DailyLog.key`), its start in the calendar it is read with, its entries in time
    /// order, and its line.
    public struct Day: Sendable, Hashable {
        public let key: String
        public let date: Date
        public let entries: [Entry]
        public let line: String?
    }

    public private(set) var entries: [Entry] = []
    /// Each day's one line, by `key(for:calendar:)`.
    public private(set) var lines: [String: String] = [:]

    public init(entries: [Entry] = [], lines: [String: String] = [:]) {
        self.entries = entries
        self.lines = lines
    }

    /// An Impact just recorded.
    public mutating func add(_ entry: Entry) {
        entries.append(entry)
    }

    /// The day's one line: trimmed, with its line breaks turned into spaces; an empty one removes it.
    public mutating func setLine(_ text: String, on date: Date, calendar: Calendar) {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        lines[Self.key(for: date, calendar: calendar)] = line.isEmpty ? nil : line
    }

    /// The days with an entry or a line, newest first, each as it was recorded; no day shows empty (UX.md → Daily
    /// review). `calendar`'s time zone places each day's start.
    public func days(calendar: Calendar) -> [Day] {
        let byDay = Dictionary(grouping: entries, by: \.day)
        return Set(byDay.keys).union(lines.keys).compactMap { key -> Day? in
            guard let date = Self.date(forKey: key, calendar: calendar) else { return nil }
            return Day(key: key, date: date, entries: (byDay[key] ?? []).sorted { $0.date < $1.date }, line: lines[key])
        }
        .sorted { $0.key > $1.key }
    }

    /// The day of `date` in `calendar`'s time zone, as "2026-11-19": Gregorian whatever calendar the user chose, so a
    /// stored key reads the same after they change it.
    public static func key(for date: Date, calendar: Calendar) -> String {
        let day = gregorian(calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    private static func date(forKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian(calendar).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

import Foundation

/// One of the user's one to three goals (PRODUCT.md → Goals).
/// Stored as its synthesized `Codable`, as is `WorkingHours`: renaming a property or case, or
/// adding a non-optional property, breaks loading stored data. Setup keeps `timesPerWeek` within 1–5.
public struct Goal: Sendable, Hashable, Codable, Identifiable {
    public enum Window: String, Sendable, Hashable, Codable { case workday, personal }

    public let id: String
    public var title: String
    /// 1–5 sessions of 60 minutes.
    public var timesPerWeek: Int
    public var window: Window

    public init(id: String, title: String, timesPerWeek: Int = 2, window: Window = .workday) {
        self.id = id
        self.title = title
        self.timesPerWeek = timesPerWeek
        self.window = window
    }
}

/// The Workday window; Personal time is the rest of 07:00–22:00 (PRODUCT.md → Goals).
public struct WorkingHours: Sendable, Hashable, Codable {
    /// `Calendar` weekday numbers: 1 is Sunday.
    public var weekdays: Set<Int>
    /// Minutes after midnight; a day without `start < end` has no Workday window.
    /// shortcut: overnight working hours (20:00–04:00) are not supported: they give no Workday window and Personal
    /// time all of 07:00–22:00; goal setup must keep `end` after `start`; support them if setup ever allows it.
    public var start: Int
    public var end: Int

    public init(weekdays: Set<Int> = [2, 3, 4, 5, 6], start: Int = 9 * 60, end: Int = 18 * 60) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
    }
}

/// A goal-time card: the goal and the earliest free slot, computed from the calendar.
public struct GoalTimeCard: Sendable, Hashable {
    public let goal: Goal
    public let slot: DateInterval
}

extension ImpactEngine {
    static let sessionLength: TimeInterval = 60 * 60
    static let busyGap: TimeInterval = 10 * 60

    /// Goal-time rules v1 (PRODUCT.md): the one goal-time card Home shows, or nil. `sessions` holds, by goal ID, the
    /// sessions Impact blocked that are still on the calendar (any week); `lastNotNow` when the user last tapped Not now.
    /// Nothing shows on the day of a Not now; Block time does not count, so the next card follows. The goal with
    /// the fewest sessions this week goes first, then the order of `goals`. `events` must cover the rest of the week
    /// (`horizon` does). `calendar` sets the days, windows, and where the week starts. Each call picks again, so the
    /// slot of a card nobody answers moves later as time passes (PRODUCT.md → Goal-time rules v1).
    public static func goalTimeCard(
        goals: [Goal], sessions: [String: [DateInterval]], lastNotNow: Date?, events: [CalendarEvent],
        now: Date, calendar: Calendar, workingHours: WorkingHours
    ) -> GoalTimeCard? {
        guard !(lastNotNow.map { calendar.isDate($0, inSameDayAs: now) } ?? false),
              let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        // Every calendar Impact reads, subscribed ones too: being busy is not needing a card (D12), and a slot wrongly
        // free would put a block over a real commitment (PRODUCT.md → Goal-time rules v1).
        let busy = events.filter { !$0.isAllDay && !$0.isCanceled && $0.participation != .declined && !$0.isFree }
            .map { $0.start ..< max($0.start, $0.end) }
        let earliest = now.addingTimeInterval(60 * 60)
        let waiting = goals.enumerated().compactMap { index, goal -> (Int, Int, GoalTimeCard)? in
            // Not `week.contains`: it includes the week's end, which starts the next week.
            let blocked = (sessions[goal.id] ?? []).filter { week.start <= $0.start && $0.start < week.end }
            guard blocked.count < goal.timesPerWeek,
                  let slot = freeSlot(
                      in: goal.window, busy: busy, skipping: Set(blocked.map { calendar.startOfDay(for: $0.start) }),
                      from: earliest, until: week.end, calendar: calendar, workingHours: workingHours)
            else { return nil }
            return (blocked.count, index, GoalTimeCard(goal: goal, slot: slot))
        }
        return waiting.min { ($0.0, $0.1) < ($1.0, $1.1) }?.2
    }

    /// The earliest 60-minute slot inside `window`, at least 10 minutes from any busy time, starting from `earliest`
    /// on a 5-minute mark and ending by `end`, on a day not in `skipping` (start of day).
    static func freeSlot(
        in window: Goal.Window, busy: [Range<Date>], skipping: Set<Date>, from earliest: Date, until end: Date,
        calendar: Calendar, workingHours: WorkingHours
    ) -> DateInterval? {
        var day = calendar.startOfDay(for: earliest)
        while day < end {
            if !skipping.contains(day) {
                for range in windows(window, on: day, calendar: calendar, workingHours: workingHours) {
                    let lower = max(range.lowerBound, earliest)
                    // A free stretch starts at the window, `earliest`, or 10 minutes after a busy time.
                    let starts = ([lower] + busy.map { $0.upperBound.addingTimeInterval(busyGap) }.filter { $0 > lower })
                        .map(onFiveMinutes).sorted()
                    for start in starts {
                        let slot = start ..< start.addingTimeInterval(sessionLength)
                        guard slot.upperBound <= min(range.upperBound, end) else { break }
                        if !busy.contains(where: {
                            $0.lowerBound < slot.upperBound.addingTimeInterval(busyGap)
                                && $0.upperBound > slot.lowerBound.addingTimeInterval(-busyGap)
                        }) {
                            return DateInterval(start: slot.lowerBound, end: slot.upperBound)
                        }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = calendar.startOfDay(for: next)
        }
        return nil
    }

    /// The goal's window on `day`, in order: Workday is the working hours on a working day; Personal time is
    /// 07:00–22:00 outside them.
    static func windows(
        _ window: Goal.Window, on day: Date, calendar: Calendar, workingHours: WorkingHours
    ) -> [Range<Date>] {
        let working = workingHours.weekdays.contains(calendar.component(.weekday, from: day))
            && workingHours.start < workingHours.end
        let minutes: [(Int, Int)] = switch window {
        case .workday: working ? [(workingHours.start, workingHours.end)] : []
        case .personal: working
            ? [(7 * 60, min(workingHours.start, 22 * 60)), (max(workingHours.end, 7 * 60), 22 * 60)]
            : [(7 * 60, 22 * 60)]
        }
        return minutes.compactMap { start, end in
            guard start < end, let from = time(start, on: day, calendar), let to = time(end, on: day, calendar),
                  from < to else { return nil }
            return from ..< to
        }
    }

    private static func time(_ minutes: Int, on day: Date, _ calendar: Calendar) -> Date? {
        minutes >= 24 * 60 ? calendar.dateInterval(of: .day, for: day)?.end
            : calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// Rounds up to a 5-minute mark, in local time too: today's time zone offsets are multiples of 15 minutes.
    private static func onFiveMinutes(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
    }
}

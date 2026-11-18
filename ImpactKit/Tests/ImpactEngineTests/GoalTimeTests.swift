import Foundation
import ImpactEngine
import Testing

/// Los Angeles differs from both UTC (CI) and KST; weeks start on Sunday unless a test changes it.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.firstWeekday = 1
    return calendar
}()
/// Thursday, 14 January 2027; its week runs from Sunday the 10th to Sunday the 17th.
private let thursday = calendar.date(from: DateComponents(year: 2027, month: 1, day: 14))!

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: thursday)!
}

private func busy(
    _ hour: Int, _ minute: Int = 0, day: Int = 0, minutes: Int = 60, _ edit: (inout CalendarEvent) -> Void = { _ in }
) -> CalendarEvent {
    let start = at(hour, minute, day: day)
    var event = CalendarEvent(id: "\(day)-\(hour):\(minute)", calendarID: "work", title: "Busy", start: start,
                              end: start.addingTimeInterval(Double(minutes) * 60))
    edit(&event)
    return event
}

private func session(_ hour: Int, day: Int) -> DateInterval {
    DateInterval(start: at(hour, day: day), duration: 3_600)
}

private let book = Goal(id: "book", title: "Write a book", window: .personal)
private let launch = Goal(id: "launch", title: "Ship the Q1 launch")

private func card(
    _ goals: [Goal], now: Date, events: [CalendarEvent] = [], sessions: [String: [DateInterval]] = [:],
    answers: [GoalAnswer] = [], calendar: Calendar = calendar, workingHours: WorkingHours = WorkingHours()
) -> GoalTimeCard? {
    ImpactEngine.goalTimeCard(goals: goals, sessions: sessions, answers: answers, events: events, now: now,
                              calendar: calendar, workingHours: workingHours)
}

@Suite struct GoalTimeTests {
    @Test("PRODUCT.md: Personal time, none blocked, the earliest free slot is Thursday 19:00")
    func personalSlot() {
        let card = card([book], now: at(17), events: [busy(18, minutes: 50)])
        #expect(card?.goal == book && card?.slot == session(19, day: 0))
    }

    @Test("PRODUCT.md: two sessions already blocked this week, so no card; last week's do not count")
    func targetMet() {
        let blocked = [session(19, day: -3), session(19, day: -2)]
        #expect(card([book], now: at(17), sessions: ["book": blocked]) == nil)
        #expect(card([book], now: at(17), sessions: ["book": [session(19, day: -7), session(19, day: -2)]])?.slot
            == session(18, day: 0))
    }

    @Test("PRODUCT.md: Workday at 11:00 with a meeting 13:00–14:00 and the next at 15:30 gives 14:10–15:10")
    func workdaySlot() {
        let card = card([launch], now: at(11), events: [busy(13), busy(15, 30)])
        #expect(card?.slot == DateInterval(start: at(14, 10), end: at(15, 10)))
    }

    @Test("PRODUCT.md: only 50-minute gaps left in the window this week, so no card")
    func noSlot() {
        let friday = [busy(9, day: 1), busy(10, 50, day: 1, minutes: 70), busy(12, 50, day: 1, minutes: 70),
                      busy(14, 50, day: 1, minutes: 70), busy(16, 50, day: 1, minutes: 70)]
        #expect(card([launch], now: at(8, day: 1), events: friday) == nil)
        #expect(card([launch], now: at(8, day: 1), events: Array(friday.dropLast()))?.slot
            == DateInterval(start: at(16, 10, day: 1), end: at(17, 10, day: 1)))
    }

    @Test("PRODUCT.md: Not now hides that goal until tomorrow; another goal can still show")
    func notNow() {
        let answers = [GoalAnswer(goalID: "book", date: at(9), blocked: false)]
        #expect(card([book], now: at(17), answers: answers) == nil)
        #expect(card([book, launch], now: at(10), answers: answers)?.goal == launch)
        #expect(card([book], now: at(8, day: 1), answers: answers)?.goal == book)
        // Block time does not hide its goal; only the session count and the daily limit hold it back.
        #expect(card([book], now: at(17), answers: [GoalAnswer(goalID: "book", date: at(9), blocked: true)])?.goal == book)
    }

    @Test("Two answers today, Block time or Not now, end goal-time cards for the day")
    func twoADay() {
        let answers = [GoalAnswer(goalID: "launch", date: at(9), blocked: true),
                       GoalAnswer(goalID: "launch", date: at(10), blocked: false)]
        #expect(card([book], now: at(17), answers: answers) == nil)
        #expect(card([book], now: at(17), answers: Array(answers.prefix(1))) != nil)
        #expect(card([book], now: at(8, day: 1), answers: answers) != nil)
    }

    @Test("A goal's two sessions are never on the same day; the fewest sessions this week goes first")
    func spreadAndOrder() {
        #expect(card([book], now: at(17), sessions: ["book": [session(7, day: 0)]])?.slot == session(7, day: 1))
        let blocked = ["launch": [session(9, day: -1)]]
        #expect(card([launch, book], now: at(10), sessions: blocked)?.goal == book)
        #expect(card([launch, book], now: at(10))?.goal == launch)
    }

    @Test("All-day, canceled, declined, and free events are not busy time; tentative ones are", arguments: [
        ("all-day", false), ("canceled", false), ("declined", false), ("free", false), ("tentative", true),
    ])
    func busyTime(_ kind: String, _ isBusy: Bool) {
        let event = busy(12) {
            switch kind {
            case "all-day": $0.isAllDay = true
            case "canceled": $0.isCanceled = true
            case "declined": $0.participation = .declined
            case "free": $0.isFree = true
            default: $0.participation = .tentative
            }
        }
        #expect(card([launch], now: at(11), events: [event])?.slot.start == (isBusy ? at(13, 10) : at(12)))
    }

    @Test("Slots start an hour from now on a 5-minute mark")
    func fiveMinutes() {
        #expect(card([launch], now: at(10, 2))?.slot.start == at(11, 5))
        #expect(card([launch], now: at(10), events: [busy(11, minutes: 47)])?.slot.start == at(12))
    }

    @Test("The week ends on the locale's first weekday; weekends are Personal time only, 07:00–22:00")
    func weekEnd() {
        #expect(card([book], now: at(21, day: 2)) == nil)
        #expect(card([launch], now: at(8, day: 2)) == nil)
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        #expect(card([book], now: at(21, day: 2), calendar: mondayFirst)?.slot == session(7, day: 3))
        #expect(card([book], now: at(8, day: 2))?.slot == session(9, day: 2))
        // A session moved to the next week's first minute counts for that week, not this one.
        #expect(card([book], now: at(17), sessions: ["book": [session(19, day: -2), session(0, day: 3)]]) != nil)
    }

    @Test("Working hours set both windows: Personal time on a working day is 07:00–22:00 outside them")
    func workingHours() {
        let hours = WorkingHours(weekdays: [2, 3, 4, 5], start: 10 * 60, end: 16 * 60)
        #expect(card([launch], now: at(8, day: 1), workingHours: hours) == nil)
        #expect(card([book], now: at(7), workingHours: hours)?.slot == session(8, day: 0))
        #expect(card([book], now: at(9), workingHours: hours)?.slot == session(16, day: 0))
        #expect(card([launch], now: at(7), workingHours: hours)?.slot == session(10, day: 0))
        // Personal time stays within 07:00–22:00 when working hours fall outside it.
        #expect(card([book], now: at(5), workingHours: WorkingHours(start: 0, end: 6 * 60))?.slot == session(7, day: 0))
    }

    @Test("An event ending before it starts does not crash the search")
    func invertedEvent() {
        #expect(card([launch], now: at(11), events: [busy(12) { $0.end = at(11) }]) != nil)
    }
}

import Foundation
import ImpactEngine
import Testing

/// Los Angeles differs from both UTC (CI) and KST, so a slip to `Calendar.current` fails somewhere.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
    calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
}

private func card(_ id: String, _ edit: (inout CalendarEvent) -> Void) throws -> ImpactCard {
    var event = CalendarEvent(id: id, calendarID: "personal", title: id, start: at(10), end: at(11))
    edit(&event)
    return try #require(try ImpactEngine().card(for: event, now: at(9)))
}

@Suite struct DailyLogTests {
    @Test("Join and Directions make entries with the card's title; a focus block's comes from its session")
    func entries() throws {
        let review = try card("Design review") { $0.url = URL(string: "https://zoom.us/j/1") }
        let dentist = try card("Dentist") { $0.structuredPlace = Place(title: "Clinic", latitude: 37.5, longitude: 127) }
        let block = try card("block") { $0.title = "Write a book"; $0.focusGoal = "Write a novel" }
        #expect(DailyLog.Entry(impactOf: review, at: at(10, 1))
                == DailyLog.Entry(cardID: "Design review", kind: .joined, title: "Design review", date: at(10, 1)))
        #expect(DailyLog.Entry(impactOf: dentist, at: at(9, 40))?.kind == .left)
        #expect(DailyLog.Entry(impactOf: block, at: at(10)) == nil)
        // A session is stamped when it ended, at its end at the latest, its length rounded to the minute.
        let session = try #require(FocusSession(card: block, now: at(10, 10)))
        let ended = DailyLog.Entry(session: session, endedAt: at(10, 59).addingTimeInterval(40))
        #expect(ended == DailyLog.Entry(cardID: "block", kind: .focused(minutes: 50), title: "Write a novel",
                                        date: at(10, 59).addingTimeInterval(40)))
        #expect(DailyLog.Entry(session: session, endedAt: at(13)).date == at(11))
        #expect(DailyLog.Entry(session: session, endedAt: at(13)).kind == .focused(minutes: 50))
    }

    @Test("Days with an entry or a line, newest first, entries in time order; no empty day")
    func days() {
        var log = DailyLog()
        log.add(DailyLog.Entry(cardID: "b", kind: .left, title: "Dentist", date: at(14)))
        log.add(DailyLog.Entry(cardID: "a", kind: .joined, title: "Standup", date: at(9)))
        log.add(DailyLog.Entry(cardID: "c", kind: .joined, title: "Retro", date: at(16, day: 13)))
        log.setLine("Quiet day", on: at(20, day: 14), calendar: calendar)
        let days = log.days(calendar: calendar)
        #expect(days.map(\.date) == [at(0), at(0, day: 14), at(0, day: 13)])
        #expect(days[0].entries.map(\.cardID) == ["a", "b"] && days[0].line == nil)
        #expect(days[1].entries.isEmpty && days[1].line == "Quiet day")
        // An entry late in the evening belongs to its local day, not to UTC's next one.
        log.add(DailyLog.Entry(cardID: "d", kind: .joined, title: "Late call", date: at(23, 30, day: 13)))
        #expect(log.days(calendar: calendar).last?.entries.map(\.cardID) == ["c", "d"])
    }

    @Test("One line: trimmed, its line breaks turned into spaces; empty removes it")
    func line() {
        var log = DailyLog()
        log.setLine("  Shipped the beta\nthen ran  \n", on: at(21), calendar: calendar)
        #expect(log.lines == ["2027-01-15": "Shipped the beta then ran"])
        log.setLine(" \n ", on: at(22), calendar: calendar)
        #expect(log.lines.isEmpty && log.days(calendar: calendar).isEmpty)
    }
}

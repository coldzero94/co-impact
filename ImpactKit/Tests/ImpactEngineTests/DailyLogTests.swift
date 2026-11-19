import Foundation
import ImpactEngine
import Testing

/// Los Angeles differs from both UTC (CI) and KST, so a slip to `Calendar.current` fails somewhere.
private let calendar = gregorian("America/Los_Angeles")

private func gregorian(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
    calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
}

private func entry(_ id: String, _ kind: DailyLog.Entry.Kind = .joined, at date: Date,
                   in calendar: Calendar = calendar) -> DailyLog.Entry {
    DailyLog.Entry(cardID: id, kind: kind, title: id, date: date, calendar: calendar)
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
        #expect(DailyLog.Entry(impactOf: review, at: at(10, 1), calendar: calendar) == entry("Design review", at: at(10, 1)))
        #expect(DailyLog.Entry(impactOf: dentist, at: at(9, 40), calendar: calendar)?.kind == .left)
        #expect(DailyLog.Entry(impactOf: block, at: at(10), calendar: calendar) == nil)
        // A session is stamped when it ended, at its end at the latest, its length rounded to the minute.
        let session = try #require(FocusSession(card: block, now: at(10, 10)))
        let ended = DailyLog.Entry(session: session, endedAt: at(10, 59).addingTimeInterval(40), calendar: calendar)
        #expect(ended == DailyLog.Entry(cardID: "block", kind: .focused(minutes: 50), title: "Write a novel",
                                        date: at(10, 59).addingTimeInterval(40), calendar: calendar))
        let late = DailyLog.Entry(session: session, endedAt: at(13), calendar: calendar)
        #expect(late.date == at(11) && late.kind == .focused(minutes: 50) && late.day == "2027-01-15")
    }

    @Test("Days with an entry or a line, newest first, entries in time order; no empty day")
    func days() {
        var log = DailyLog()
        log.add(entry("b", .left, at: at(14)))
        log.add(entry("a", at: at(9)))
        log.add(entry("c", at: at(16, day: 13)))
        log.setLine("Quiet day", on: at(20, day: 14), calendar: calendar)
        let days = log.days(calendar: calendar)
        #expect(days.map(\.key) == ["2027-01-15", "2027-01-14", "2027-01-13"])
        #expect(days.map(\.date) == [at(0), at(0, day: 14), at(0, day: 13)])
        #expect(days[0].entries.map(\.cardID) == ["a", "b"] && days[0].line == nil)
        #expect(days[1].entries.isEmpty && days[1].line == "Quiet day")
        // An entry late in the evening belongs to its local day, not to UTC's next one.
        log.add(entry("d", at: at(23, 30, day: 13)))
        #expect(log.days(calendar: calendar).last?.entries.map(\.cardID) == ["c", "d"])
    }

    @Test("A day stays as it was recorded after travel: the evening's entry and line stay together")
    func travel() {
        var log = DailyLog()
        // Joined at 20:00 in Los Angeles and wrote the day's line, then flew to Seoul, where it is the next afternoon.
        log.add(entry("call", at: at(20)))
        log.setLine("Long day", on: at(21), calendar: calendar)
        let seoul = gregorian("Asia/Seoul")
        let days = log.days(calendar: seoul)
        #expect(days.count == 1 && days[0].key == "2027-01-15")
        #expect(days[0].entries.map(\.cardID) == ["call"] && days[0].line == "Long day")
        #expect(seoul.dateComponents([.day, .hour], from: days[0].date) == DateComponents(day: 15, hour: 0))
        // It keeps the zone it was recorded in, so it still reads 20:00, the time the user saw that evening.
        #expect(days[0].entries[0].timeZone == calendar.timeZone)
    }

    @Test("Day keys are Gregorian whatever calendar the user chose, so a line keeps its day after a change")
    func otherCalendars() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        var log = DailyLog()
        log.setLine("Songkran plans", on: at(20), calendar: buddhist)
        log.add(entry("call", at: at(19), in: buddhist))
        #expect(log.lines.keys.sorted() == ["2027-01-15"] && log.entries[0].day == "2027-01-15")
        let days = log.days(calendar: calendar)
        #expect(days.count == 1 && days[0].date == at(0) && days[0].line == "Songkran plans")
    }

    @Test("A card has one entry, as it has one Impact: a second is ignored")
    func oneEntryPerCard() {
        var log = DailyLog()
        log.add(entry("review", at: at(10, 1)))
        log.add(entry("review", at: at(10, 20)))
        #expect(log.entries == [entry("review", at: at(10, 1))])
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

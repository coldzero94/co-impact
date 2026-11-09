import Foundation
import ImpactEngine
import Testing

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()
private let start = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 10))!

/// A hybrid card: Join meeting (primary), Directions, and Open link.
private func hybridCard() throws -> ImpactCard {
    var event = CalendarEvent(id: "town-hall", calendarID: "personal", title: "Town hall",
                              start: start, end: start.addingTimeInterval(3_600))
    event.url = URL(string: "https://zoom.us/j/1")
    event.structuredPlace = Place(title: "Synthetic hall", latitude: 37.5, longitude: 127)
    event.notes = "Agenda: https://example.com/agenda"
    let card = try #require(try ImpactEngine().card(for: event, now: start.addingTimeInterval(-600)))
    #expect(card.kind == .hybrid && card.actions.count == 3)
    return card
}

@Suite struct ActionLogTests {
    @Test("Only the primary action records an Impact, and only once per card")
    func primaryRecordsOnce() throws {
        let card = try hybridCard()
        var log = ActionLog()
        let secondary = log.record(card.actions[1], on: card, at: start)
        #expect(!secondary)
        #expect(log.isDone(card.actions[1], on: card) && !log.isDone(card.actions[0], on: card))
        #expect(log.completedCardIDs.isEmpty)

        let first = log.record(card.actions[0], on: card, at: start)
        let again = log.record(card.actions[0], on: card, at: start.addingTimeInterval(60))
        #expect(first && !again)
        #expect(log.completedCardIDs == ["town-hall"])
        #expect(log.impacts == ["town-hall": start])
    }

    @Test("Impacts count on the day they were recorded, in the given calendar")
    func countsByDay() throws {
        let card = try hybridCard()
        var log = ActionLog()
        // 23:30 in Los Angeles is already the next day in UTC.
        let lateEvening = try #require(calendar.date(bySettingHour: 23, minute: 30, second: 0, of: start))
        log.record(card.actions[0], on: card, at: lateEvening)
        #expect(log.impactCount(on: start, calendar: calendar) == 1)
        #expect(log.impactCount(on: start.addingTimeInterval(86_400), calendar: calendar) == 0)
    }

    @Test("Recording feeds Home: the done card leaves Next up and fills a ring segment")
    func feedsHome() throws {
        let card = try hybridCard()
        let event = CalendarEvent(id: "town-hall", calendarID: "personal", title: "Town hall",
                                  start: start, end: start.addingTimeInterval(3_600), url: URL(string: "https://zoom.us/j/1"))
        var log = ActionLog()
        let now = start.addingTimeInterval(-600)
        let home = { try ImpactEngine().home(events: [event], now: now, calendar: calendar,
                                             completedCardIDs: log.completedCardIDs,
                                             impactsToday: log.impactCount(on: now, calendar: calendar)) }
        #expect(try home().nextUp?.id == "town-hall")
        log.record(card.actions[0], on: card, at: now)
        let after = try home()
        #expect(after.nextUp == nil && after.doneCardIDs == ["town-hall"])
        #expect(after.impactsToday == 1 && after.ringSegments == 1)
    }
}

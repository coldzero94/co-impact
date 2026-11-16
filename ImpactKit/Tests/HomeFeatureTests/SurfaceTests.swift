import Foundation
@testable import HomeFeature
import ImpactEngine
@testable import LiveSurfaces
import Testing

private let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()
private let midnight = losAngeles.date(from: DateComponents(year: 2027, month: 1, day: 15))!
private func at(_ hour: Double, day: Int = 0) -> Date { midnight.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }

private func meeting(_ id: String, _ hour: Double, day: Int = 0) -> CalendarEvent {
    CalendarEvent(id: id, calendarID: "work", title: id, start: at(hour, day: day), end: at(hour + 1, day: day),
                  url: URL(string: "https://zoom.us/j/1"))
}

@Suite struct SurfaceTests {
    private let engine = try! ImpactEngine()
    private let none = SurfaceState(completed: [:], suppressionRules: [])

    @Test("The widget follows Home's Next up through Soon, Now, and expiry, then the next card")
    func moments() throws {
        let moments = NextCards.moments(events: [meeting("Review", 10), meeting("Sync", 13)], state: none, now: at(9),
                                        calendar: losAngeles, engine: engine)
        let at945 = try #require(moments.first { $0.date == at(9.75) })
        #expect(moments.first?.date == at(9) && moments.first?.card?.id == "Review" && moments.first?.soonOrNow == false)
        #expect(at945.card?.id == "Review" && at945.soonOrNow)
        // Review ends at 11:00 (an online card expires at its end); Sync leads from then.
        #expect(moments.first { $0.date == at(11) }?.card?.id == "Sync")
        #expect(moments.map(\.date) == moments.map(\.date).sorted())
    }

    @Test("Back-to-back changes share an entry, and a busy day stops at 24")
    func capAndDedupe() throws {
        // Review ends at 11:00 when Sync starts: one entry at 11:00.
        let pair = NextCards.moments(events: [meeting("Review", 10), meeting("Sync", 11)], state: none, now: at(9),
                                     calendar: losAngeles, engine: engine)
        #expect(pair.count { $0.date == at(11) } == 1)
        let busy = (0 ..< 12).map { meeting("M\($0)", 9.5 + Double($0)) }
        #expect(NextCards.moments(events: busy, state: none, now: at(9), calendar: losAngeles, engine: engine).count == 24)
    }

    @Test("Entries fall exactly on each change of phase (Soon, start, end of Now, expiry) and at midnight")
    func changes() throws {
        let place = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)
        var visit = meeting("Visit", 14)
        visit.url = nil
        visit.structuredPlace = place
        // An in-person card that ends before 15 minutes leaves at its end.
        var keys = meeting("Keys", 12)
        keys.url = nil
        keys.structuredPlace = place
        keys.end = at(12) + 5 * 60
        let moments = NextCards.moments(events: [keys, visit, meeting("Call", 16)], state: none, now: at(9),
                                        calendar: losAngeles, engine: engine)
        // Keys: Soon 11:30, start 12:00, leaves 12:05. Visit: Soon 13:30, start 14:00, expiry 14:15.
        // Call (online): Soon 15:45, start 16:00, end of Now 16:10, end 17:00. Midnight starts the ring over.
        let expected = [9, 11.5, 12, 12 + 1.0 / 12, 13.5, 14, 14.25, 15.75, 16, 16 + 1.0 / 6, 17, 24].map { at($0) }
        #expect(moments.map(\.date) == expected)
        #expect(moments.first { $0.date == at(12 + 1.0 / 12) }?.card?.id == "Visit")
        #expect(moments.first { $0.date == at(14.25) }?.card?.id == "Call")
        #expect(moments.last?.card == nil)
    }

    @Test("The medium widget's second row is the next card still to do; the ring counts the day's Impacts")
    func laterAndRing() throws {
        let events = [meeting("Done", 8), meeting("Review", 10), meeting("Sync", 13), meeting("Wrap", 15)]
        let state = SurfaceState(completed: ["Done": at(8), "Yesterday": at(9, day: -1)], suppressionRules: [])
        let first = try #require(NextCards.moments(events: events, state: state, now: at(9), calendar: losAngeles,
                                                   engine: engine).first)
        #expect(first.card?.id == "Review" && first.later?.id == "Sync")
        // One Impact today (Done; yesterday's does not count) plus three cards still to do.
        #expect(first.impactsToday == 1 && first.ringSegments == 4)
    }

    @Test("The widget rereads after the last change ahead, at least hourly, and in an hour with nothing ahead")
    func reloadDate() {
        #expect(NextCards.reloadDate(after: [at(9)], now: at(9)) == at(10))
        #expect(NextCards.reloadDate(after: [at(9), at(9.5)], now: at(9)) == at(9.5))
        #expect(NextCards.reloadDate(after: [at(9), at(12)], now: at(9)) == at(10))
    }

    @Test("Done and dismissed cards are skipped; tomorrow's first card shows once today has none")
    func state() throws {
        let events = [meeting("Done", 10), meeting("Muted", 11), meeting("Tomorrow", 8, day: 1)]
        let state = SurfaceState(completed: ["Done": at(8)], suppressionRules: [.occurrence(id: "Muted")])
        let moments = NextCards.moments(events: events, state: state, now: at(9), calendar: losAngeles, engine: engine)
        #expect(moments.first?.card?.id == "Tomorrow")
    }

    @Test("The surface state survives the App Group store; data that does not decode reads as none")
    func store() throws {
        let suite = "impact-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SurfaceStore(defaults: defaults)
        #expect(store.load() == nil)
        let state = SurfaceState(completed: ["a": at(9)], suppressionRules: [.title(calendarID: "work", title: "Standup")], runToken: "secret")
        store.save(state)
        #expect(store.load() == state)
        defaults.set(Data("not json".utf8), forKey: SurfaceStore.key)
        #expect(store.load() == nil)
    }

    @Test("Home tells the widgets the cards done in the last two days or still on Home, and its dismissal rules")
    @MainActor func homeState() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 10), now: at(9.9)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(9.9))
        // Long runs from three days ago to tomorrow and was joined on its first day: still on Home, so still done.
        var long = meeting("Long", 9, day: -3)
        long.end = at(18, day: 1)
        log.restore(["Old": at(9, day: -3), "Long": at(9, day: -3)])
        let model = try HomeModel(events: [meeting("Review", 10), meeting("Sync", 13), long], now: at(10),
                                  calendar: losAngeles, log: log)
        model.dismiss(try #require(model.snapshot.cards.first { $0.id == "Sync" }), similar: false)
        #expect(model.surfaceState(runToken: "secret").completedCardIDs == ["Review", "Long"])
        #expect(model.surfaceState(runToken: "secret").suppressionRules == [.occurrence(id: "Sync")])
    }

    @Test("A run link reaches the card a widget shows before Home lists it (tomorrow's, before 18:00)")
    @MainActor func runnableTomorrow() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 14), now: at(14)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(14))
        // Review is joined and still on Home, so Home keeps tomorrow off its list; the widget shows tomorrow's card.
        let events = [meeting("Review", 14), meeting("Tomorrow", 8, day: 1)]
        let model = try HomeModel(events: events, now: at(14.2), calendar: losAngeles, log: log)
        let shown = try #require(NextCards.moments(events: events, state: model.surfaceState(runToken: "secret"),
                                                   now: at(14.2), calendar: losAngeles, engine: engine).first?.card)
        #expect(shown.id == "Tomorrow" && !model.snapshot.cards.contains { $0.id == "Tomorrow" })
        #expect(model.runnableCard(id: "Tomorrow")?.id == "Tomorrow")
    }
}

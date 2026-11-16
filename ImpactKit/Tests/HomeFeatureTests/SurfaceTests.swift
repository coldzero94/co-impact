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
    private let none = SurfaceState(completedCardIDs: [], suppressionRules: [])

    @Test("The widget follows Home's Next up through Soon, Now, and expiry, then the next card")
    func moments() throws {
        let moments = NextCards.moments(events: [meeting("Review", 10), meeting("Sync", 13)], state: none, now: at(9),
                                        calendar: losAngeles, engine: engine)
        let at945 = try #require(moments.first { $0.date == at(9.75) })
        #expect(moments.first?.date == at(9) && moments.first?.card?.id == "Review" && moments.first?.soonOrNow == false)
        #expect(at945.card?.id == "Review" && at945.soonOrNow)
        // Review ends at 11:00 (an online card expires at its end); Sync leads from then.
        #expect(moments.first { $0.date == at(11) }?.card?.id == "Sync")
        #expect(moments.map(\.date) == moments.map(\.date).sorted() && moments.count <= 24)
    }

    @Test("Entries fall on every change of phase: Soon, start, end of Now, expiry, and the end")
    func changes() throws {
        var visit = meeting("Visit", 14)
        visit.url = nil
        visit.structuredPlace = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)
        let moments = NextCards.moments(events: [visit, meeting("Call", 16)], state: none, now: at(9),
                                        calendar: losAngeles, engine: engine)
        // In person: Soon at 13:30, start 14:00, expiry 14:15 (when the card leaves); online: Soon 15:45, start 16:00,
        // end of Now 16:10, end 17:00. The other offsets fall in between and change nothing visible.
        let dates = Set(moments.map(\.date))
        for hour in [9, 13.5, 14, 14.25, 15.75, 16, 16 + 1.0 / 6, 17] { #expect(dates.contains(at(hour)), "\(hour)") }
        #expect(moments.first { $0.date == at(14.25) }?.card?.id == "Call")
        #expect(moments.first { $0.date == at(17) }?.card == nil)
    }

    @Test("Done and dismissed cards are skipped; tomorrow's first card shows once today has none")
    func state() throws {
        let events = [meeting("Done", 10), meeting("Muted", 11), meeting("Tomorrow", 8, day: 1)]
        let state = SurfaceState(completedCardIDs: ["Done"], suppressionRules: [.occurrence(id: "Muted")])
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
        let state = SurfaceState(completedCardIDs: ["a"], suppressionRules: [.title(calendarID: "work", title: "Standup")])
        store.save(state)
        #expect(store.load() == state)
        defaults.set(Data("not json".utf8), forKey: SurfaceStore.key)
        #expect(store.load() == nil)
    }

    @Test("Home tells the widgets the cards done in the last two days and its dismissal rules")
    @MainActor func homeState() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 10), now: at(9.9)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(9.9))
        log.restore(["Old": at(9, day: -3)])
        let model = try HomeModel(events: [meeting("Review", 10), meeting("Sync", 13)], now: at(10), calendar: losAngeles, log: log)
        model.dismiss(try #require(model.snapshot.cards.first { $0.id == "Sync" }), similar: false)
        #expect(model.surfaceState.completedCardIDs == ["Review"])
        #expect(model.surfaceState.suppressionRules == [.occurrence(id: "Sync")])
    }
}

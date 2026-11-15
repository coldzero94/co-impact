import Foundation
import ImpactEngine
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func event(_ id: String, series: String? = nil, title: String = "Standup", calendar: String = "work") -> CalendarEvent {
    CalendarEvent(id: id, calendarID: calendar, title: title, start: now.addingTimeInterval(3_600),
                  end: now.addingTimeInterval(5_400), seriesID: series, url: URL(string: "https://zoom.us/j/1"))
}

@Suite struct DismissalsTests {
    private let engine = try! ImpactEngine()

    @Test("Not needed hides that occurrence only")
    func notNeeded() {
        var dismissals = Dismissals()
        dismissals.dismiss(event("mon", series: "s"), at: now)
        #expect(engine.card(for: event("mon", series: "s"), now: now, suppressionRules: dismissals.rules) == nil)
        #expect(engine.card(for: event("tue", series: "s"), now: now, suppressionRules: dismissals.rules) != nil)
    }

    @Test("Don't suggest mutes the series, or else the same title on the same calendar")
    func mute() {
        var series = Dismissals()
        series.mute(like: event("mon", series: "s"))
        #expect(engine.card(for: event("tue", series: "s"), now: now, suppressionRules: series.rules) == nil)
        #expect(engine.card(for: event("other", series: "t"), now: now, suppressionRules: series.rules) != nil)

        var title = Dismissals()
        title.mute(like: event("one-off"))
        #expect(engine.card(for: event("again"), now: now, suppressionRules: title.rules) == nil)
        #expect(engine.card(for: event("again", calendar: "home"), now: now, suppressionRules: title.rules) != nil)
        #expect(engine.card(for: event("again", title: "Review"), now: now, suppressionRules: title.rules) != nil)
    }

    @Test("Not needed lasts until the event ends but at least two days, even for a multi-day one; mutes stay")
    func prune() throws {
        var dismissals = Dismissals()
        var conference = event("conference")
        conference.end = now.addingTimeInterval(3 * 86_400)
        dismissals.dismiss(conference, at: now)
        dismissals.dismiss(event("standup"), at: now)
        dismissals.mute(like: event("x", series: "s"))
        // A day later the standup has ended, but if it was moved later (same ID) it must stay hidden.
        #expect(Set(dismissals.pruned(now: now.addingTimeInterval(86_400)).occurrences.keys) == ["conference", "standup"])
        let twoDaysLater = dismissals.pruned(now: now.addingTimeInterval(2 * 86_400))
        #expect(Set(twoDaysLater.occurrences.keys) == ["conference"] && twoDaysLater.muted == dismissals.muted)
        #expect(dismissals.pruned(now: now.addingTimeInterval(3 * 86_400)).occurrences.isEmpty)
    }

    @Test("Dismissals survive encoding")
    func codable() throws {
        var dismissals = Dismissals()
        dismissals.dismiss(event("mon"), at: now)
        dismissals.mute(like: event("x", series: "s"))
        dismissals.mute(like: event("y"))
        let decoded = try JSONDecoder().decode(Dismissals.self, from: JSONEncoder().encode(dismissals))
        #expect(decoded == dismissals)
    }
}

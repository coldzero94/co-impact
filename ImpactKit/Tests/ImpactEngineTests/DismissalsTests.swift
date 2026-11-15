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
        series.mute(like: event("mon", series: "s"), at: now)
        #expect(engine.card(for: event("tue", series: "s"), now: now, suppressionRules: series.rules) == nil)
        #expect(engine.card(for: event("other", series: "t"), now: now, suppressionRules: series.rules) != nil)

        var title = Dismissals()
        title.mute(like: event("one-off"), at: now)
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
        dismissals.mute(like: event("x", series: "s"), at: now)
        // A day later the standup has ended, but if it was moved later (same ID) it must stay hidden.
        #expect(Set(dismissals.pruned(now: now.addingTimeInterval(86_400)).occurrences.keys) == ["conference", "standup"])
        let twoDaysLater = dismissals.pruned(now: now.addingTimeInterval(2 * 86_400))
        #expect(Set(twoDaysLater.occurrences.keys) == ["conference"] && twoDaysLater.muted == dismissals.muted)
        #expect(dismissals.pruned(now: now.addingTimeInterval(3 * 86_400)).occurrences.isEmpty)
    }

    @Test("Don't suggest on an untitled one-off only dismisses it; an untitled series is still muted")
    func untitled() {
        var dismissals = Dismissals()
        dismissals.mute(like: event("blank", title: ""), at: now)
        #expect(dismissals.muted.isEmpty && Array(dismissals.occurrences.keys) == ["blank"])
        #expect(engine.card(for: event("other blank", title: ""), now: now, suppressionRules: dismissals.rules) != nil)

        var series = Dismissals()
        series.mute(like: event("mon", series: "s", title: ""), at: now)
        #expect(series.muted == [.series(calendarID: "work", seriesID: "s")] && series.occurrences.isEmpty)
    }

    /// The JSON users have stored today. If this stops decoding, an update would set every user's mutes aside.
    @Test("The stored format stays readable")
    func storedFormat() throws {
        let json = #"{"occurrences":{"mon":800000000},"muted":[{"series":{"calendarID":"work","seriesID":"s"}},{"title":{"calendarID":"work","title":"Review"}}]}"#
        let decoded = try JSONDecoder().decode(Dismissals.self, from: Data(json.utf8))
        #expect(decoded.occurrences == ["mon": Date(timeIntervalSinceReferenceDate: 800_000_000)])
        #expect(decoded.muted == [.series(calendarID: "work", seriesID: "s"), .title(calendarID: "work", title: "Review")])
    }

    @Test("Dismissals survive encoding")
    func codable() throws {
        var dismissals = Dismissals()
        dismissals.dismiss(event("mon"), at: now)
        dismissals.mute(like: event("x", series: "s"), at: now)
        dismissals.mute(like: event("y"), at: now)
        let decoded = try JSONDecoder().decode(Dismissals.self, from: JSONEncoder().encode(dismissals))
        #expect(decoded == dismissals)
    }
}

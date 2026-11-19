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

/// The event Block time created for the goal "book", 10:00–11:00, marked as Home marks it.
private let focusBlock: CalendarEvent = {
    var event = CalendarEvent(id: "block", calendarID: "personal", title: "Write a book", start: at(10), end: at(11))
    event.focusGoal = "Write a novel"
    return event
}()

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

    @Test("The medium widget's Later column is the next card still to do; the ring counts the entry day's Impacts")
    func laterAndRing() throws {
        // Done starts with Review but was joined early, so it is neither Next up nor Later.
        let events = [meeting("Done", 10), meeting("Review", 10), meeting("Sync", 13), meeting("Wrap", 15)]
        let state = SurfaceState(completed: ["Done": at(9.78), "Yesterday": at(9, day: -1)], suppressionRules: [])
        let moments = NextCards.moments(events: events, state: state, now: at(9.8), calendar: losAngeles, engine: engine)
        let first = try #require(moments.first)
        #expect(first.card?.id == "Review" && first.later?.id == "Sync")
        // One Impact today (Done; yesterday's does not count) plus three cards still to do.
        #expect(first.impactsToday == 1 && first.ringSegments == 4)
        // Once Sync is Next up while Review still runs, Later is Wrap, never the earlier Review.
        let overlap = [meeting("Review", 10), meeting("Sync", 10.5), meeting("Wrap", 15)]
        let soon = try #require(NextCards.moments(events: overlap, state: state, now: at(10.3), calendar: losAngeles,
                                                  engine: engine).first)
        #expect(soon.card?.id == "Sync" && soon.later?.id == "Wrap")
        // Midnight starts the ring over.
        #expect(moments.last?.date == at(24) && moments.last?.impactsToday == 0)
    }

    @Test("Siri runs the card that runs now among those with the action asked for; tomorrow's waits for its day")
    func nextForIntents() throws {
        var visit = meeting("Visit", 14)
        visit.url = nil
        visit.structuredPlace = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)
        var errand = visit
        errand.id = "Errand"
        errand.start = at(10.5)
        errand.end = at(10.75)
        // Done (9:30) was joined and Muted dismissed, so Review (11:00) is the next meeting; Errand (10:30), a place
        // but no link, is not one. Errand is the next place.
        let events = [meeting("Done", 9.5), errand, meeting("Muted", 10.75), meeting("Review", 11), visit,
                      meeting("Tomorrow", 8, day: 1)]
        let state = SurfaceState(completed: ["Done": at(9.6)], suppressionRules: [.occurrence(id: "Muted")])
        let home = NextCards.home(events: events, state: state, now: at(10), calendar: losAngeles, engine: engine)
        #expect(NextCards.next(.join, in: home, now: at(10), calendar: losAngeles)?.id == "Review")
        #expect(NextCards.next(.directions, in: home, now: at(10), calendar: losAngeles)?.id == "Errand")
        // In the evening Home lists tomorrow's meeting, but it is not joined the evening before.
        let evening = NextCards.home(events: events, state: state, now: at(20), calendar: losAngeles, engine: engine)
        #expect(evening.cards.contains { $0.id == "Tomorrow" })
        #expect(NextCards.next(.join, in: evening, now: at(20), calendar: losAngeles) == nil)
        // Back to back: at 13:54 Sync (13:00, joined elsewhere, so not done here) is ending and Review is in Soon.
        let backToBack = [meeting("Sync", 13), meeting("Review", 14)]
        let late = NextCards.home(events: backToBack, state: none, now: at(13.9), calendar: losAngeles, engine: engine)
        #expect(NextCards.next(.join, in: late, now: at(13.9), calendar: losAngeles)?.id == "Review")
        // Overlapping: at 10:30 Home's Next up is Review (10:00), not the Workshop running since 9:00.
        var workshop = meeting("Workshop", 9)
        workshop.end = at(12)
        let overlap = [workshop, meeting("Review", 10)]
        let mid = NextCards.home(events: overlap, state: none, now: at(10.5), calendar: losAngeles, engine: engine)
        #expect(mid.nextUp?.id == "Review")
        #expect(NextCards.next(.join, in: mid, now: at(10.5), calendar: losAngeles)?.id == "Review")
    }

    @Test("A run request runs the primary action, or the kind an App Intent asked for if the card has it")
    func pickAction() throws {
        var hybrid = meeting("Hybrid", 11)
        hybrid.structuredPlace = Place(title: "Synthetic office", latitude: 37.5, longitude: 127)
        let card = try #require(engine.card(for: hybrid, now: at(10)))
        let online = try #require(engine.card(for: meeting("Review", 11), now: at(10)))
        #expect(RunRequest(cardID: card.id).pick(from: card) == card.primaryAction)
        let directions = try #require(RunRequest(cardID: card.id, action: .directions).pick(from: card))
        let join = try #require(RunRequest(cardID: card.id, action: .join).pick(from: card))
        guard case .directions = directions.kind, case .joinMeeting = join.kind else {
            Issue.record("Picked \(directions.kind) and \(join.kind)")
            return
        }
        #expect(RunRequest(cardID: online.id, action: .directions).pick(from: online) == nil)
    }

    @Test("The widgets and the control run today's Next up, or before midnight a card of tomorrow in its Now phase")
    func runnableMoments() throws {
        let evening = NextCards.moments(events: [meeting("Tomorrow", 8, day: 1)], state: none, now: at(20),
                                        calendar: losAngeles, engine: engine).first
        #expect(evening?.card?.id == "Tomorrow" && evening?.runnable == false)
        // A meeting at 00:05 is in its Now phase from 23:55, when its Live Activity runs it; in Soon at 23:52, not yet.
        let notYet = NextCards.moments(events: [meeting("Early", 1.0 / 12, day: 1)], state: none,
                                       now: at(23 + 52.0 / 60), calendar: losAngeles, engine: engine)
        #expect(notYet.first?.card?.id == "Early" && notYet.first?.runnable == false)
        #expect(notYet.first { $0.date == at(23 + 55.0 / 60) }?.runnable == true)
        let soon = NextCards.moments(events: [meeting("Early", 1.0 / 12, day: 1)], state: none, now: at(23 + 55.0 / 60),
                                     calendar: losAngeles, engine: engine).first
        #expect(soon?.card?.id == "Early" && soon?.runnable == true)
        let soonHome = NextCards.home(events: [meeting("Early", 1.0 / 12, day: 1)], state: none,
                                      now: at(23 + 55.0 / 60), calendar: losAngeles, engine: engine)
        #expect(NextCards.runnable(in: soonHome, now: at(23 + 55.0 / 60), calendar: losAngeles)?.id == "Early")
        let joined = NextCards.next(.join, in: soonHome, now: at(23 + 55.0 / 60), calendar: losAngeles)
        #expect(joined?.id == "Early")
        // Before midnight a meeting ends that was joined elsewhere (not done here) while Early is in its Now phase:
        // every surface runs Early, as its Live Activity does, and the widgets show it. At 23:52 Late still runs.
        let both = [meeting("Late", 23), meeting("Early", 1.0 / 12, day: 1)]
        let edge = NextCards.home(events: both, state: none, now: at(23 + 55.0 / 60), calendar: losAngeles,
                                  engine: engine)
        #expect(edge.nextUp?.id == "Late")
        let before = NextCards.home(events: both, state: none, now: at(23 + 52.0 / 60), calendar: losAngeles,
                                    engine: engine)
        #expect(NextCards.runnable(in: before, now: at(23 + 52.0 / 60), calendar: losAngeles)?.id == "Late")
        #expect(NextCards.runnable(in: edge, now: at(23 + 55.0 / 60), calendar: losAngeles)?.id == "Early")
        #expect(NextCards.next(.join, in: edge, now: at(23 + 55.0 / 60), calendar: losAngeles)?.id == "Early")
        let shown = NextCards.moments(events: both, state: none, now: at(23 + 55.0 / 60), calendar: losAngeles,
                                      engine: engine).first
        #expect(shown?.card?.id == "Early" && shown?.runnable == true)
        // 23:30 yesterday to 00:30: at 00:05 it is still today's Next up.
        let late = NextCards.moments(events: [meeting("Call", 23.5, day: -1)], state: none, now: at(1.0 / 12),
                                     calendar: losAngeles, engine: engine).first
        #expect(late?.card?.id == "Call" && late?.runnable == true)
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
        let block = try #require(engine.card(for: focusBlock, now: at(10)))
        let state = SurfaceState(completed: ["a": at(9)], suppressionRules: [.title(calendarID: "work", title: "Standup")],
                                 runToken: "secret", focusBlocks: ["block": "Write a novel"],
                                 focus: FocusSession(card: block, now: at(10)))
        store.save(state)
        #expect(store.load() == state)
        defaults.set(Data("not json".utf8), forKey: SurfaceStore.key)
        #expect(store.load() == nil)
    }

    @Test("Home tells the widgets the cards done in the last two days or still fetched, and its dismissal rules")
    @MainActor func homeState() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 10), now: at(9.9)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(9.9))
        // Long runs from three days ago to tomorrow and was joined on its first day: still fetched, so still done.
        var long = meeting("Long", 9, day: -3)
        long.end = at(18, day: 1)
        // Moved was joined three days ago, then moved to the day after tomorrow: not on Home, but still fetched.
        log.restore(["Old": at(9, day: -3), "Long": at(9, day: -3), "Moved": at(9, day: -3)])
        let model = try HomeModel(events: [meeting("Review", 10), meeting("Sync", 13), long, meeting("Moved", 9, day: 2)],
                                  now: at(10), calendar: losAngeles, log: log)
        model.dismiss(try #require(model.snapshot.cards.first { $0.id == "Sync" }), similar: false)
        let state = model.surfaceState(runToken: "secret")
        #expect(state.completed == ["Review": at(9.9), "Long": at(9, day: -3), "Moved": at(9, day: -3)]
                && state.runToken == "secret")
        #expect(state.suppressionRules == [.occurrence(id: "Sync")])
    }

    @Test("Background refresh, from the widgets' state, wants the Live Activities Home requested")
    @MainActor func backgroundLiveCards() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 10), now: at(9.9)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(9.9))
        // Moved was joined three days ago, then moved to tomorrow morning.
        log.restore(["Moved": at(9, day: -3)])
        let events = [meeting("Review", 10), meeting("Sync", 13), meeting("Call", 15), meeting("Moved", 9, day: 1)]
        let model = try HomeModel(events: events, now: at(10), calendar: losAngeles, log: log)
        model.dismiss(try #require(model.snapshot.cards.first { $0.id == "Sync" }), similar: false)
        let home = NextCards.home(events: events, state: model.surfaceState(runToken: "secret"), now: at(10),
                                  calendar: losAngeles, engine: engine)
        // Done Review and Moved and dismissed Sync stay out: otherwise a background sync would end Call's activity
        // for a second card or give a done card an alert.
        #expect(model.liveCards(runToken: "secret").map(\.cardID) == ["Call"])
        #expect(home.liveActivityCards.compactMap { LiveCard($0, runToken: "secret") } == model.liveCards(runToken: "secret"))
    }

    @Test("A run request reaches the cards Home lists, Next up past its Now phase included, not tomorrow's early")
    @MainActor func runnableCards() throws {
        var log = ActionLog()
        let review = try #require(engine.card(for: meeting("Review", 14), now: at(14)))
        _ = log.record(try #require(review.primaryAction), on: review, at: at(14))
        // Review is joined and still on Home, so Home keeps tomorrow off its list; the widget shows tomorrow's card
        // without a button, and a request for it runs nothing.
        let events = [meeting("Review", 14), meeting("Tomorrow", 8, day: 1)]
        let model = try HomeModel(events: events, now: at(14.2), calendar: losAngeles, log: log)
        let shown = try #require(NextCards.moments(events: events, state: model.surfaceState(runToken: "secret"),
                                                   now: at(14.2), calendar: losAngeles, engine: engine).first)
        #expect(shown.card?.id == "Tomorrow" && !shown.runnable)
        #expect(model.runnableCard(id: "Tomorrow") == nil)
        // Past its Now phase, a meeting is still Home's Next up but wants no Live Activity: it runs too.
        let late = try HomeModel(events: [meeting("Call", 10)], now: at(10.3), calendar: losAngeles, log: ActionLog())
        #expect(late.snapshot.nextUp?.id == "Call" && late.snapshot.liveActivityCards.isEmpty)
        #expect(late.runnableCard(id: "Call")?.id == "Call" && late.runnableCard(id: "Unknown") == nil)
    }

    @Test("Focus blocks reach every surface as Home marks them; background refresh keeps the session's Live Activity")
    @MainActor func focusSurfaces() throws {
        var block = focusBlock
        block.focusGoal = nil // as the calendar gives it
        let events = [block, meeting("Sync", 13)]
        let goals = GoalSettings(goals: [Goal(id: "book", title: "Write a novel", timesPerWeek: 1)], offered: true)
        let records = GoalRecords(sessions: [
            GoalSession(goalID: "book", eventID: "block", title: "Write a book", start: at(10), end: at(11)),
        ])
        let model = try HomeModel(events: events, now: at(9.75), calendar: losAngeles, goals: goals, goalRecords: records)
        let state = model.surfaceState(runToken: "secret")
        #expect(state.focusBlocks == ["block": "Write a novel"] && state.focus == nil)
        // The widgets show the block as Home does, with its button.
        let first = try #require(NextCards.moments(events: events, state: state, now: at(9.75), calendar: losAngeles,
                                                   engine: engine).first)
        #expect(first.card?.kind == .focusBlock && first.card?.title == "Write a novel" && first.runnable)
        // Before a session its Live Activity alerts at the default level; once one runs, it shows the session, at once.
        let before = try #require(model.liveCards(runToken: "secret").first { $0.cardID == "block" })
        #expect(!before.timeSensitive && before.focusSince == nil)
        #expect(model.startFocus(on: try #require(model.snapshot.nextUp)))
        let focusing = model.surfaceState(runToken: "secret")
        let background = NextCards.home(events: events, state: focusing, now: at(9.75), calendar: losAngeles, engine: engine)
        let wanted = LiveCard.wanted(in: background, runToken: "secret", focus: focusing.focus)
        #expect(wanted == model.liveCards(runToken: "secret") && wanted.map(\.cardID) == ["block", "Sync"])
        #expect(wanted[0].focusSince == at(9.75) && wanted[1].focusSince == nil)
        let requests = LiveCard.toRequest(wanted: wanted, existing: [before], now: at(9.75))
        #expect(requests.startNow == [wanted[0]] && requests.schedule == [wanted[1]])
    }
}

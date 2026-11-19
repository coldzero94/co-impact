import Foundation
@testable import HomeFeature
import ImpactEngine
import LiveSurfaces
import Testing

private let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    losAngeles.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: hour, minute: minute))!
}

/// The event Block time created for "Write a book", 10:00–11:00, still titled as it was then, and a meeting at 13:00.
private let block = CalendarEvent(id: "block", calendarID: "personal", title: "Write a book", start: at(10), end: at(11))
private let meeting = CalendarEvent(id: "meeting", calendarID: "work", title: "Meeting", start: at(13), end: at(14),
                                    url: URL(string: "https://zoom.us/j/1"))
private let novel = Goal(id: "book", title: "Write a novel", timesPerWeek: 1)
private let records = GoalRecords(sessions: [
    GoalSession(goalID: "book", eventID: "block", title: "Write a book", start: at(10), end: at(11)),
])

/// What a model stored, in order.
@MainActor private final class Saved {
    var focus: [FocusSession?] = []
    var impacts: [[String: Date]] = []
    var logs: [DailyLog] = []
}

@MainActor private func model(at now: Date, events: [CalendarEvent] = [block, meeting], goals: [Goal] = [novel],
                              records: GoalRecords = records, focus: FocusSession? = nil,
                              saved: Saved = Saved()) throws -> HomeModel {
    try HomeModel(events: events, now: now, calendar: losAngeles,
                  goals: GoalSettings(goals: goals, offered: true), goalRecords: records, focus: focus,
                  saveImpacts: { saved.impacts.append($0) }, saveFocus: { saved.focus.append($0) },
                  saveDailyLog: { saved.logs.append($0) })
}

@MainActor private func blockCard(_ model: HomeModel) throws -> ImpactCard {
    try #require(model.snapshot.cards.first { $0.id == "block" })
}

@Suite @MainActor struct FocusTests {
    @Test("A blocked session shows as a focus block with its goal's title; a removed goal's block is a plain event")
    func focusBlock() throws {
        let model = try model(at: at(9))
        let card = try blockCard(model)
        #expect(card.kind == .focusBlock && card.title == "Write a novel" && model.snapshot.nextUp?.id == "block")
        model.update(events: [block, meeting], now: at(9, 56))
        #expect(model.liveCards(runToken: "secret").map(\.cardID).contains("block"))
        model.setGoals([], workingHours: WorkingHours())
        #expect(model.snapshot.cards.map(\.id) == ["meeting"])
    }

    @Test("Start focus works from the block's Soon phase; End focus under 10 minutes records nothing, from 10 the Impact")
    func startAndEnd() throws {
        let saved = Saved()
        let model = try model(at: at(9, 44), saved: saved)
        #expect(!model.startFocus(on: try blockCard(model)) && model.focus == nil && saved.focus.isEmpty)
        model.update(events: [block, meeting], now: at(9, 45))
        #expect(model.startFocus(on: try blockCard(model)))
        let session = try #require(model.focus)
        #expect(session.cardID == "block" && session.start == at(9, 45) && session.end == at(11))
        #expect(saved.focus == [session])
        // Started again later, it keeps running as it was.
        model.update(events: [block, meeting], now: at(9, 47))
        #expect(model.startFocus(on: try blockCard(model)) && model.focus == session && saved.focus == [session])
        model.update(events: [block, meeting], now: at(9, 50))
        #expect(!model.endFocus() && model.focus == nil && saved.focus.last == .some(nil))
        #expect(saved.impacts.isEmpty && model.focusImpact == nil && model.snapshot.doneCardIDs.isEmpty)
        #expect(model.startFocus(on: try blockCard(model)))
        model.update(events: [block, meeting], now: at(10))
        #expect(model.endFocus())
        #expect(saved.impacts.last == ["block": at(10)] && model.focusImpact == "block")
        #expect(model.snapshot.doneCardIDs == ["block"] && model.snapshot.impactsToday == 1)
        // The short session left no entry; this one does, with the goal's title.
        #expect(saved.logs == [DailyLog(entries: [
            DailyLog.Entry(cardID: "block", kind: .focused(minutes: 10), title: "Write a novel", date: at(10),
                           calendar: losAngeles),
        ])])
        // A block records one Impact: done, it does not start again.
        #expect(!model.startFocus(on: try blockCard(model)) && model.focus == nil)
    }

    @Test("One session runs at a time: Start focus on another block ends the first, with its Impact")
    func oneAtATime() throws {
        var other = block
        other.id = "other"
        other.title = "Ship the launch"
        other.start = at(10, 30)
        other.end = at(11, 30)
        let launch = Goal(id: "launch", title: "Ship the launch", timesPerWeek: 1)
        let both = GoalRecords(sessions: records.sessions + [
            GoalSession(goalID: "launch", eventID: "other", title: "Ship the launch", start: at(10, 30), end: at(11, 30)),
        ])
        let saved = Saved()
        let model = try model(at: at(10), events: [block, other, meeting], goals: [novel, launch], records: both, saved: saved)
        #expect(model.startFocus(on: try blockCard(model)))
        model.update(events: [block, other, meeting], now: at(10, 20))
        #expect(model.startFocus(on: try #require(model.snapshot.cards.first { $0.id == "other" })))
        #expect(model.focus?.cardID == "other" && model.focus?.start == at(10, 20))
        #expect(saved.impacts.last == ["block": at(10, 20)] && model.focusImpact == "block")
        #expect(saved.logs.last?.entries.map(\.cardID) == ["block"])
    }

    @Test("A session ends with its block, or once its block leaves its Soon or Now phase on Home, with its Impact",
          arguments: ["ended", "extended", "moved", "deleted", "dismissed"])
    func sessionEnds(_ way: String) throws {
        let saved = Saved()
        let model = try model(at: at(10), saved: saved)
        #expect(model.startFocus(on: try blockCard(model)))
        switch way {
        case "ended": model.update(events: [block, meeting], now: at(11, 5))
        case "extended":
            // Extended in Calendar: the session still ends where the block ended when focus started.
            var longer = block
            longer.end = at(11, 30)
            model.update(events: [longer, meeting], now: at(11, 5))
        case "moved":
            // Moved to the afternoon in Calendar: still listed, but no longer the block the session ran in.
            var later = block
            later.start = at(15)
            later.end = at(16)
            model.update(events: [later, meeting], now: at(10, 30))
            #expect(model.snapshot.cards.contains { $0.id == "block" })
        case "deleted": model.update(events: [meeting], now: at(10, 30))
        default:
            model.update(events: [block, meeting], now: at(10, 30))
            model.dismiss(try blockCard(model), similar: false)
        }
        #expect(model.focus == nil && saved.focus.last == .some(nil))
        // A session stops at its block's end, however late Impact sees it.
        #expect(saved.impacts.last == ["block": ["ended", "extended"].contains(way) ? at(11) : at(10, 30)])
        #expect(model.focusImpact == "block" && model.snapshot.impactsToday == 1)
        // Its daily log entry keeps the goal's title, even with the block gone.
        #expect(saved.logs.last?.entries.map(\.title) == ["Write a novel"])
        // Still listed, the block shows done.
        if ["extended", "moved"].contains(way) { #expect(model.snapshot.doneCardIDs == ["block"]) }
    }

    @Test("A stored session runs on after a relaunch; one whose block ended meanwhile ends at launch with its Impact")
    func restored() throws {
        let session = try #require(FocusSession(card: try blockCard(try model(at: at(10))), now: at(10)))
        #expect(try model(at: at(10, 30), focus: session).focus == session)
        let saved = Saved()
        let relaunched = try model(at: at(12), focus: session, saved: saved)
        #expect(relaunched.focus == nil && saved.focus == [nil] && saved.impacts == [["block": at(11)]])
        #expect(saved.logs.last?.entries.map(\.kind) == [.focused(minutes: 60)])
    }

    @Test("The running session survives the store in its format; an ended one is stored as none")
    func store() throws {
        let suite = "impact-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsStore<FocusSession?>(defaults)
        #expect(store.load() == nil)
        // A session stored before step 13 has no goal's title: it does not decode and is set aside.
        defaults.set(Data(#"{"cardID":"block","start":0,"end":3600}"#.utf8), forKey: "focusSession")
        #expect(store.load() == nil && defaults.data(forKey: "focusSession.unreadable") != nil)
        defaults.set(Data(#"{"cardID":"block","title":"Write a novel","start":0,"end":3600}"#.utf8), forKey: "focusSession")
        let session = try #require(store.load() ?? nil)
        #expect(session.cardID == "block" && session.title == "Write a novel"
                && session.start == Date(timeIntervalSinceReferenceDate: 0)
                && session.end == Date(timeIntervalSinceReferenceDate: 3_600))
        store.save(nil)
        #expect(store.load() == .some(nil))
        store.save(session)
        #expect(store.load() == .some(session))
    }
}

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
}

@MainActor private func model(at now: Date, events: [CalendarEvent] = [block, meeting], focus: FocusSession? = nil,
                              saved: Saved = Saved()) throws -> HomeModel {
    try HomeModel(events: events, now: now, calendar: losAngeles,
                  goals: GoalSettings(goals: [novel], offered: true), goalRecords: records, focus: focus,
                  saveImpacts: { saved.impacts.append($0) }, saveFocus: { saved.focus.append($0) })
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
        // Its Live Activity waits for the surfaces to see focus blocks (`liveCards`).
        model.update(events: [block, meeting], now: at(9, 56))
        #expect(model.snapshot.liveActivityCards.map(\.id).contains("block"))
        #expect(!model.liveCards(runToken: "secret").map(\.cardID).contains("block"))
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
        // Started again, it keeps running as it was.
        #expect(model.startFocus(on: try blockCard(model)) && model.focus == session)
        model.update(events: [block, meeting], now: at(9, 50))
        #expect(!model.endFocus() && model.focus == nil && saved.focus.last == .some(nil))
        #expect(saved.impacts.isEmpty && model.focusImpact == nil && model.snapshot.doneCardIDs.isEmpty)
        #expect(model.startFocus(on: try blockCard(model)))
        model.update(events: [block, meeting], now: at(10))
        #expect(model.endFocus())
        #expect(saved.impacts.last == ["block": at(10)] && model.focusImpact?.cardID == "block")
        #expect(model.snapshot.doneCardIDs == ["block"] && model.snapshot.impactsToday == 1)
    }

    @Test("A session ends with its block, or once its block leaves Home, and records its Impact then", arguments: [
        "ended", "deleted", "dismissed",
    ])
    func sessionEnds(_ way: String) throws {
        let saved = Saved()
        let model = try model(at: at(10), saved: saved)
        #expect(model.startFocus(on: try blockCard(model)))
        switch way {
        case "ended": model.update(events: [block, meeting], now: at(11, 5))
        case "deleted": model.update(events: [meeting], now: at(10, 30))
        default:
            model.update(events: [block, meeting], now: at(10, 30))
            model.dismiss(try blockCard(model), similar: false)
        }
        #expect(model.focus == nil && saved.focus.last == .some(nil))
        // A session stops at its block's end, however late Impact sees it.
        #expect(saved.impacts.last == ["block": way == "ended" ? at(11) : at(10, 30)])
        #expect(model.focusImpact?.cardID == "block")
    }

    @Test("A stored session runs on after a relaunch; one whose block ended meanwhile ends at launch with its Impact")
    func restored() throws {
        let session = try #require(FocusSession(card: try blockCard(try model(at: at(10))), now: at(10)))
        #expect(try model(at: at(10, 30), focus: session).focus == session)
        let saved = Saved()
        let relaunched = try model(at: at(12), focus: session, saved: saved)
        #expect(relaunched.focus == nil && saved.focus == [nil] && saved.impacts == [["block": at(11)]])
    }

    @Test("The running session survives the store in its format; an ended one is stored as none")
    func store() throws {
        let suite = "impact-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsStore<FocusSession?>(defaults)
        #expect(store.load() == nil)
        defaults.set(Data(#"{"cardID":"block","start":0,"end":3600}"#.utf8), forKey: "focusSession")
        let session = try #require(store.load() ?? nil)
        #expect(session.cardID == "block" && session.start == Date(timeIntervalSinceReferenceDate: 0)
                && session.end == Date(timeIntervalSinceReferenceDate: 3_600))
        store.save(nil)
        #expect(store.load() == .some(nil))
        store.save(session)
        #expect(store.load() == .some(session))
    }
}

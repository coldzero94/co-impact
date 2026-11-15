import Foundation
@testable import HomeFeature
import ImpactEngine
import Testing

private let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()
private let morning = losAngeles.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 9))!

private func meeting(_ id: String, at start: Date) -> CalendarEvent {
    CalendarEvent(id: id, calendarID: "work", title: id, start: start, end: start.addingTimeInterval(3_600),
                  url: URL(string: "https://zoom.us/j/1"))
}

/// A file in a fresh temporary folder, removed after the test.
private func withFile(_ body: (ImpactFile) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(ImpactFile(url: folder.appending(path: "impacts.json")))
}

@Suite struct LiveDataTests {
    @Test("Impacts survive a save and load; no file yet means none")
    func roundTrip() throws {
        try withFile { file in
            #expect(file.load().isEmpty)
            try file.save(["review": morning])
            #expect(file.load() == ["review": morning])
        }
    }

    @Test("An unreadable file is set aside, not overwritten by the next save")
    func unreadable() throws {
        try withFile { file in
            try Data("not json".utf8).write(to: file.url)
            #expect(file.load().isEmpty)
            let folder = file.url.deletingLastPathComponent()
            let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path())
            #expect(kept.count == 1 && kept[0].hasPrefix("impacts.unreadable-"))
            try file.save(["review": morning])
            #expect(file.load() == ["review": morning])
        }
    }

    @Test("Recording saves every Impact once; an update moves the clock and keeps them")
    @MainActor func recordAndUpdate() throws {
        var saved: [[String: Date]] = []
        let events = [meeting("review", at: morning.addingTimeInterval(600)), meeting("sync", at: morning.addingTimeInterval(7_200))]
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles,
                                  log: ActionLog(impacts: ["standup": morning.addingTimeInterval(-3_600)])) { saved.append($0) }
        #expect(model.snapshot.impactsToday == 1 && model.snapshot.nextUp?.id == "review")

        let review = try #require(model.snapshot.nextUp)
        let first = model.record(try #require(review.primaryAction), on: review)
        let again = model.record(try #require(review.primaryAction), on: review)
        #expect(first && !again && saved.count == 1 && saved[0].keys.sorted() == ["review", "standup"])

        let later = morning.addingTimeInterval(7_000)
        model.update(events: events, now: later)
        #expect(model.now == later && model.snapshot.nextUp?.id == "sync" && model.snapshot.impactsToday == 2)
        model.update(events: [], now: later)
        #expect(model.snapshot.nextUp == nil && model.snapshot.impactsToday == 2)
    }
}

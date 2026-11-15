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
    @Test("Impacts survive a save and load, to the sub-second; no file yet means none and leaves no file")
    func roundTrip() throws {
        try withFile { file in
            #expect(file.load() == [:])
            #expect(!FileManager.default.fileExists(atPath: file.url.path()))
            let stamp = morning.addingTimeInterval(0.123_456)
            try file.save(["review": stamp])
            #expect(file.load() == ["review": stamp])
        }
    }

    @Test("The stored format stays readable: card IDs to seconds since 2001")
    func format() throws {
        try withFile { file in
            try Data(#"{"review":800000000.5}"#.utf8).write(to: file.url)
            #expect(file.load() == ["review": Date(timeIntervalSinceReferenceDate: 800_000_000.5)])
        }
    }

    @Test("A file that does not decode is set aside with its bytes, not overwritten by the next save")
    func undecodable() throws {
        try withFile { file in
            try Data("not json".utf8).write(to: file.url)
            #expect(file.load() == [:])
            let folder = file.url.deletingLastPathComponent()
            let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path())
            #expect(kept.count == 1 && kept[0].hasPrefix("impacts.unreadable-"))
            #expect(try Data(contentsOf: folder.appending(path: kept[0])) == Data("not json".utf8))
            try file.save(["review": morning])
            #expect(file.load() == ["review": morning])
        }
    }

    @Test("A file that cannot be read now is left in place, and load says not to save over it")
    func unreadableNow() throws {
        try withFile { file in
            // A folder at the file's path fails to read without being missing, like a locked file.
            try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
            #expect(file.load() == nil)
            var isFolder: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: file.url.path(), isDirectory: &isFolder) && isFolder.boolValue)
        }
    }

    @Test("The saver skips while stored Impacts are unreadable, then merges them in once they read")
    func saverWaitsForStoredImpacts() throws {
        try withFile { file in
            let earlier = morning.addingTimeInterval(-3_600)
            try file.save(["standup": earlier])
            // Unreadable but replaceable, as a locked file can be: only the saver's guard keeps it.
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.url.path())
            let save = file.saver(stored: file.load())
            save(["review": morning])
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path())
            #expect(file.load() == ["standup": earlier])

            save(["review": morning])
            #expect(file.load() == ["standup": earlier, "review": morning])
        }
    }

    @Test("On a fresh install the saver writes the first Impact; a merge keeps each card's first stamp")
    func saverFreshAndMerge() throws {
        try withFile { file in
            let save = file.saver(stored: file.load())
            save(["review": morning])
            #expect(file.load() == ["review": morning])
        }
        try withFile { file in
            try file.save(["review": morning])
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.url.path())
            let save = file.saver(stored: file.load())
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path())
            save(["review": morning.addingTimeInterval(600)])
            #expect(file.load() == ["review": morning])
        }
    }

    @Test("Logged errors show domain and code, the underlying error's too, and never the description")
    func loggedErrors() {
        let cause = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let error = NSError(domain: "Domain", code: 1,
                            userInfo: [NSUnderlyingErrorKey: cause, NSLocalizedDescriptionKey: "secret path"])
        #expect(error.logged == "Domain 1 (NSPOSIXErrorDomain 13)")
    }

    @Test("Impacts read after launch join Home's log and are stored together")
    @MainActor func restoreLateImpacts() throws {
        var saved: [String: Date] = [:]
        let model = try HomeModel(events: [meeting("review", at: morning.addingTimeInterval(600))], now: morning,
                                  calendar: losAngeles) { saved = $0 }
        #expect(model.snapshot.impactsToday == 0)
        model.restore(["standup": morning.addingTimeInterval(-3_600), "review": morning.addingTimeInterval(-60)])
        #expect(model.snapshot.impactsToday == 2 && model.snapshot.nextUp == nil)
        #expect(saved == ["standup": morning.addingTimeInterval(-3_600), "review": morning.addingTimeInterval(-60)])
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

    @Test("Across midnight, yesterday's Impacts stop counting and a new one is stamped with the new day")
    @MainActor func acrossMidnight() throws {
        var saved: [String: Date] = [:]
        let event = meeting("review", at: morning.addingTimeInterval(600))
        let model = try HomeModel(events: [event], now: morning, calendar: losAngeles) { saved = $0 }
        let review = try #require(model.snapshot.nextUp)
        _ = model.record(try #require(review.primaryAction), on: review)
        #expect(model.snapshot.impactsToday == 1)

        let nextMorning = morning.addingTimeInterval(86_400)
        let tomorrows = meeting("standup", at: nextMorning.addingTimeInterval(600))
        model.update(events: [tomorrows], now: nextMorning)
        #expect(model.snapshot.impactsToday == 0)
        let standup = try #require(model.snapshot.nextUp)
        _ = model.record(try #require(standup.primaryAction), on: standup)
        #expect(saved["standup"] == nextMorning && saved["review"] == morning && model.snapshot.impactsToday == 1)
    }
}

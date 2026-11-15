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

    @Test("On a fresh install the saver writes the first Impact; a merge keeps each card's earlier stamp")
    func saverFreshAndMerge() throws {
        try withFile { file in
            let save = file.saver(stored: file.load())
            save(["review": morning])
            #expect(file.load() == ["review": morning])
        }
        try withFile { file in
            try file.save(["review": morning])
            let save = file.saver(stored: file.load())
            save(["review": morning.addingTimeInterval(600)])
            #expect(file.load() == ["review": morning])
            save(["review": morning.addingTimeInterval(-600)])
            #expect(file.load() == ["review": morning.addingTimeInterval(-600)])
        }
    }

    @Test("Logged errors show domain and code, the underlying error's too, and never the description")
    func loggedErrors() {
        let cause = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let error = NSError(domain: "Domain", code: 1,
                            userInfo: [NSUnderlyingErrorKey: cause, NSLocalizedDescriptionKey: "secret path"])
        #expect(error.logged == "Domain 1 (NSPOSIXErrorDomain 13)")
        #expect(NSError(domain: "D", code: 2).logged == "D 2")
    }

    @Test("Impacts read after launch join the session's own, and all are stored together")
    @MainActor func restoreLateImpacts() throws {
        var saved: [String: Date] = [:]
        let events = [meeting("review", at: morning.addingTimeInterval(600)), meeting("sync", at: morning.addingTimeInterval(7_200))]
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles) { saved = $0 }
        let review = try #require(model.snapshot.nextUp)
        _ = model.record(try #require(review.primaryAction), on: review)
        model.restore(["standup": morning.addingTimeInterval(-3_600), "sync": morning.addingTimeInterval(-60)])
        #expect(model.snapshot.impactsToday == 3 && model.snapshot.nextUp == nil)
        #expect(saved == ["review": morning, "standup": morning.addingTimeInterval(-3_600), "sync": morning.addingTimeInterval(-60)])
    }

    @Test("Not needed hides the card and its ring segment, is stored, and survives an update")
    @MainActor func notNeeded() throws {
        var saved: [Dismissals] = []
        let events = [meeting("standup", at: morning.addingTimeInterval(600)), meeting("review", at: morning.addingTimeInterval(3_600))]
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles, saveDismissals: { saved.append($0) })
        #expect(model.snapshot.ringSegments == 2)
        model.dismiss(try #require(model.snapshot.nextUp), similar: false)
        #expect(model.snapshot.cards.map(\.id) == ["review"] && model.snapshot.ringSegments == 1)
        #expect(saved.last?.occurrences == ["standup": morning.addingTimeInterval(2 * 86_400)])
        model.update(events: events, now: morning.addingTimeInterval(60))
        #expect(model.snapshot.cards.map(\.id) == ["review"])
    }

    @Test("Don't suggest mutes the series: tonight's and tomorrow's occurrences both leave")
    @MainActor func muteSeries() throws {
        var saved: [Dismissals] = []
        let evening = morning.addingTimeInterval(10 * 3_600) // 19:00
        var tonight = meeting("sync-mon", at: evening.addingTimeInterval(1_800))
        tonight.seriesID = "sync"
        var tomorrow = tonight
        tomorrow.id = "sync-tue"
        tomorrow.start = morning.addingTimeInterval(86_400)
        tomorrow.end = tomorrow.start.addingTimeInterval(3_600)
        let model = try HomeModel(events: [tonight, tomorrow], now: evening, calendar: losAngeles,
                                  saveDismissals: { saved.append($0) })
        #expect(model.snapshot.cards.map(\.id) == ["sync-mon", "sync-tue"])
        model.dismiss(try #require(model.snapshot.nextUp), similar: true)
        #expect(model.snapshot.cards.isEmpty && saved.last?.muted == [.series(calendarID: "work", seriesID: "sync")])
    }

    @Test("Stored dismissals hide their cards from the first snapshot")
    @MainActor func startsWithStoredDismissals() throws {
        var dismissals = Dismissals()
        let events = [meeting("standup", at: morning.addingTimeInterval(600)), meeting("review", at: morning.addingTimeInterval(3_600))]
        dismissals.dismiss(events[0], at: morning.addingTimeInterval(-60))
        dismissals.mute(like: events[1], at: morning.addingTimeInterval(-60))
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles, dismissals: dismissals)
        #expect(model.snapshot.cards.isEmpty)
    }

    @Test("A dismissed event moved past the lapse comes back in a running app, as after a relaunch")
    @MainActor func dismissalLapsesWhileRunning() throws {
        var event = meeting("review", at: morning.addingTimeInterval(3_600))
        let model = try HomeModel(events: [event], now: morning, calendar: losAngeles)
        model.dismiss(try #require(model.snapshot.nextUp), similar: false)
        // Moved, same ID, to three days later.
        event.start += 3 * 86_400
        event.end += 3 * 86_400
        // Moved to tomorrow morning first: still hidden while the dismissal holds.
        var soon = event
        soon.start = morning.addingTimeInterval(86_400)
        soon.end = soon.start.addingTimeInterval(3_600)
        model.update(events: [soon], now: morning.addingTimeInterval(10 * 3_600))
        #expect(model.snapshot.cards.isEmpty)
        // Seen the evening before its new day, after the two-day lapse: it comes back.
        let eve = morning.addingTimeInterval(2 * 86_400 + 10 * 3_600)
        model.update(events: [event], now: eve)
        #expect(model.snapshot.tomorrowMorning.map(\.id) == ["review"])
    }

    @Test("Dismissals survive the store, without lapsed ones; data that does not decode is kept aside")
    func dismissalStore() throws {
        let suite = "impact-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DismissalStore(defaults: defaults)
        #expect(store.load(now: morning) == Dismissals())
        var dismissals = Dismissals()
        dismissals.dismiss(meeting("old", at: morning.addingTimeInterval(-3 * 86_400)), at: morning.addingTimeInterval(-3 * 86_400))
        dismissals.dismiss(meeting("recent", at: morning), at: morning.addingTimeInterval(-3_600))
        store.save(dismissals)
        #expect(store.load(now: morning).occurrences.keys.sorted() == ["recent"])

        defaults.set(Data("not json".utf8), forKey: DismissalStore.key)
        #expect(store.load(now: morning) == Dismissals())
        #expect(defaults.data(forKey: "\(DismissalStore.key).unreadable") == Data("not json".utf8))
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

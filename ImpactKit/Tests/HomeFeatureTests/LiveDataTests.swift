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

/// A fresh `UserDefaults` suite, removed after the test.
private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "impact-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
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

    @Test("Stored dismissals hide their cards from the first snapshot, after updates, and stay in later saves")
    @MainActor func startsWithStoredDismissals() throws {
        var saved: [Dismissals] = []
        var dismissals = Dismissals()
        let events = [meeting("standup", at: morning.addingTimeInterval(600)), meeting("review", at: morning.addingTimeInterval(3_600)),
                      meeting("sync", at: morning.addingTimeInterval(7_200))]
        dismissals.dismiss(events[0], at: morning.addingTimeInterval(-60))
        dismissals.mute(like: events[1], at: morning.addingTimeInterval(-60))
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles, dismissals: dismissals,
                                  saveDismissals: { saved.append($0) })
        #expect(model.snapshot.cards.map(\.id) == ["sync"])
        model.update(events: events, now: morning.addingTimeInterval(60))
        #expect(model.snapshot.cards.map(\.id) == ["sync"])
        model.dismiss(try #require(model.snapshot.nextUp), similar: false)
        let last = try #require(saved.last)
        #expect(Set(last.occurrences.keys) == ["standup", "sync"] && last.muted == dismissals.muted)
    }

    @Test("Dismissing a done card keeps its Impact; a card with no event left changes and saves nothing")
    @MainActor func dismissDoneOrGone() throws {
        var saved: [Dismissals] = []
        let events = [meeting("standup", at: morning.addingTimeInterval(-300)), meeting("review", at: morning.addingTimeInterval(3_600))]
        let model = try HomeModel(events: events, now: morning, calendar: losAngeles, saveDismissals: { saved.append($0) })
        let standup = try #require(model.snapshot.nextUp)
        _ = model.record(try #require(standup.primaryAction), on: standup)
        model.dismiss(standup, similar: false)
        #expect(model.snapshot.cards.map(\.id) == ["review"])
        #expect(model.snapshot.impactsToday == 1 && model.snapshot.ringSegments == 2)

        let review = try #require(model.snapshot.nextUp)
        model.update(events: [], now: morning.addingTimeInterval(60))
        model.dismiss(review, similar: true)
        model.update(events: events, now: morning.addingTimeInterval(120))
        #expect(saved.count == 1 && model.snapshot.cards.map(\.id) == ["review"])
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

    @Test("Dismissals survive the store; data that does not decode is kept aside")
    func dismissalStore() throws {
        try withDefaults { defaults in
            let store = DefaultsStore<Dismissals>(defaults)
            #expect(store.load() == nil)
            var dismissals = Dismissals()
            dismissals.dismiss(meeting("recent", at: morning), at: morning.addingTimeInterval(-3_600))
            store.save(dismissals)
            #expect(store.load() == dismissals)

            // The key and format users have stored: a new format sets every user's dismissals aside, a new key loses them.
            let json = #"{"occurrences":{"recent":900000000},"muted":[{"title":{"calendarID":"work","title":"Review"}}]}"#
            defaults.set(Data(json.utf8), forKey: "dismissals")
            #expect(store.load()?.muted == [.title(calendarID: "work", title: "Review")])

            defaults.set(Data("not json".utf8), forKey: "dismissals")
            #expect(store.load() == nil)
            #expect(defaults.data(forKey: "dismissals.unreadable") == Data("not json".utf8))
            #expect(defaults.data(forKey: "dismissals") == nil)
        }
    }

    @Test("Goals survive the store in the format users have stored")
    func goalStore() throws {
        try withDefaults { defaults in
            let store = DefaultsStore<GoalSettings>(defaults)
            let settings = GoalSettings(goals: [Goal(id: "book", title: "Write a book", timesPerWeek: 3, window: .personal)],
                                        workingHours: WorkingHours(weekdays: [2, 3], start: 600, end: 960), offered: true)
            store.save(settings)
            #expect(store.load() == settings)

            let json = #"{"goals":[{"id":"run","title":"Run","timesPerWeek":2,"window":"workday"},"#
                + #"{"id":"book","title":"Book","timesPerWeek":1,"window":"personal"}],"#
                + #""workingHours":{"weekdays":[2,3,4,5,6],"start":540,"end":1080},"offered":false}"#
            defaults.set(Data(json.utf8), forKey: "goals")
            #expect(store.load() == GoalSettings(goals: [Goal(id: "run", title: "Run"),
                                                         Goal(id: "book", title: "Book", timesPerWeek: 1, window: .personal)]))
        }
    }

    @Test("A new start keeps the working day's end at least 15 minutes after it, by 23:59")
    func workingHoursStart() {
        var hours = WorkingHours()
        hours.setStart(17 * 60 + 50)
        #expect(hours.start == 17 * 60 + 50 && hours.end == 18 * 60 + 50)
        hours.setStart(9 * 60)
        #expect(hours.end == 18 * 60 + 50)
        hours.setStart(23 * 60 + 44)
        #expect(hours.end == 23 * 60 + 59)
    }

    @Test("Goal records load from the key and format users have stored")
    func goalRecordsStore() throws {
        try withDefaults { defaults in
            let sessions = #"{"sessions":[{"goalID":"book","eventID":"e1","title":"Write a book","start":0,"end":3600}]"#
            let start = Date(timeIntervalSinceReferenceDate: 0)
            let session = GoalSession(goalID: "book", eventID: "e1", title: "Write a book", start: start,
                                      end: start.addingTimeInterval(3_600))
            // The first build stored today's answers; they no longer count, and its sessions still load.
            let stored = [
                (#","answers":[{"goalID":"book","date":0,"blocked":true}]}"#, GoalRecords(sessions: [session])),
                (#","lastNotNow":0}"#, GoalRecords(sessions: [session], lastNotNow: start)),
            ]
            for (rest, records) in stored {
                defaults.set(Data((sessions + rest).utf8), forKey: "goalRecords")
                #expect(DefaultsStore<GoalRecords>(defaults).load() == records)
            }
        }
    }

    @Test("The daily log loads from the key and format users will have stored")
    func dailyLogStore() throws {
        try withDefaults { defaults in
            let zone = #""timeZone":{"identifier":"America\/Los_Angeles"}"#
            let json = #"{"entries":[{"cardID":"r","kind":{"joined":{}},"title":"Design review","date":0,"# + zone + "},"
                + #"{"cardID":"d","kind":{"left":{}},"title":"Dentist","date":60,"# + zone + "},"
                + #"{"cardID":"b","kind":{"focused":{"minutes":50}},"title":"Write a book","date":3600,"# + zone + "}],"
                + #""lines":{"2000-12-31":"Good day"}}"#
            defaults.set(Data(json.utf8), forKey: "dailyLog")
            // Midnight UTC on 2001-01-01 is still December 31 in Los Angeles.
            let start = Date(timeIntervalSinceReferenceDate: 0)
            #expect(DefaultsStore<DailyLog>(defaults).load() == DailyLog(entries: [
                DailyLog.Entry(cardID: "r", kind: .joined, title: "Design review", date: start, calendar: losAngeles),
                DailyLog.Entry(cardID: "d", kind: .left, title: "Dentist", date: start.addingTimeInterval(60),
                               calendar: losAngeles),
                DailyLog.Entry(cardID: "b", kind: .focused(minutes: 50), title: "Write a book",
                               date: start.addingTimeInterval(3_600), calendar: losAngeles),
            ], lines: ["2000-12-31": "Good day"]))
        }
    }

    @Test("Each Impact adds its daily log entry and stores the log; preparation adds none")
    @MainActor func dailyLog() throws {
        var saved: [DailyLog] = []
        var dentist = CalendarEvent(id: "dentist", calendarID: "personal", title: "Dentist",
                                    start: morning.addingTimeInterval(5 * 3_600), end: morning.addingTimeInterval(6 * 3_600))
        dentist.structuredPlace = Place(title: "Synthetic clinic", latitude: 37.5, longitude: 127)
        // Yesterday's page is stored already: today's entries join it.
        let yesterday = DailyLog.Entry(cardID: "standup", kind: .joined, title: "Standup",
                                       date: morning.addingTimeInterval(-86_400), calendar: losAngeles)
        let stored = DailyLog(entries: [yesterday], lines: ["2027-01-14": "Calm day"])
        let model = try HomeModel(events: [meeting("review", at: morning.addingTimeInterval(600)), dentist], now: morning,
                                  calendar: losAngeles, dailyLog: stored, saveDailyLog: { saved.append($0) })
        // Directions five hours ahead is preparation: no Impact, so no entry.
        let visit = try #require(model.snapshot.cards.first { $0.id == "dentist" })
        #expect(!model.record(try #require(visit.primaryAction), on: visit) && saved.isEmpty)
        let review = try #require(model.snapshot.nextUp)
        #expect(model.record(try #require(review.primaryAction), on: review))
        let joined = DailyLog.Entry(cardID: "review", kind: .joined, title: "review", date: morning, calendar: losAngeles)
        #expect(saved == [DailyLog(entries: [yesterday, joined], lines: ["2027-01-14": "Calm day"])]
                && model.dailyLog == saved.last)
    }

    @Test("The daily review: today's one line is stored when it changes; the Today row from 18:00 or after the last card")
    @MainActor func dailyReview() throws {
        var saved: [DailyLog] = []
        let model = try HomeModel(events: [meeting("review", at: morning.addingTimeInterval(600))], now: morning,
                                  calendar: losAngeles, saveDailyLog: { saved.append($0) })
        // A card still to do in the morning: no Today row.
        #expect(!model.showsTodayRow)
        model.setLine("  Shipped the beta ", on: model.now)
        model.setLine("Shipped the beta", on: model.now)
        #expect(model.line(on: model.now) == "Shipped the beta" && saved.count == 1)
        #expect(model.reviewDays.first?.line == "Shipped the beta")
        // A review opened before midnight keeps its line on its own day after it.
        model.setLine("Late night", on: morning.addingTimeInterval(-10 * 3_600))
        #expect(model.line(on: morning) == "Shipped the beta" && model.reviewDays.map(\.line) == ["Shipped the beta", "Late night"])
        // Once the day's last card is done, the row shows, as from 18:00 on any day.
        let review = try #require(model.snapshot.nextUp)
        #expect(model.record(try #require(review.primaryAction), on: review) && model.showsTodayRow)
        let evening = try HomeModel(events: [], now: morning.addingTimeInterval(9 * 3_600), calendar: losAngeles)
        #expect(evening.showsTodayRow)
        let empty = try HomeModel(events: [], now: morning, calendar: losAngeles)
        #expect(!empty.showsTodayRow)
    }

    @Test("The weekly summary reads the week's days in order, from three entries on; other weeks stay out")
    @MainActor func weekLog() throws {
        // Friday 2027-01-15; the week starts on Sunday in this calendar (Gregorian, `firstWeekday` 1).
        let entry = { (id: String, kind: DailyLog.Entry.Kind, days: Double) in
            DailyLog.Entry(cardID: id, kind: kind, title: id, date: morning.addingTimeInterval(days * 86_400),
                           calendar: losAngeles)
        }
        // Saturday the 9th belongs to the week before; a day with only a line shows but does not count.
        var log = DailyLog(entries: [entry("Standup", .joined, -3), entry("Dentist", .left, -1),
                                     entry("Last week", .joined, -6)])
        log.setLine("Long walk", on: morning.addingTimeInterval(-86_400), calendar: losAngeles)
        log.setLine("Rest day", on: morning.addingTimeInterval(-2 * 86_400), calendar: losAngeles)
        let two = try HomeModel(events: [], now: morning, calendar: losAngeles, dailyLog: log)
        #expect(two.weekLog(on: morning) == nil)
        log.add(entry("Write a book", .focused(minutes: 50), 0))
        let three = try HomeModel(events: [], now: morning, calendar: losAngeles, dailyLog: log)
        #expect(three.weekLog(on: morning) == """
            Tuesday
            - Joined Standup

            Wednesday
            Line: Rest day

            Thursday
            - Left for Dentist
            Line: Long walk

            Friday
            - 50 min on Write a book
            """)
        // Where weeks start on Monday, Saturday the 9th and Sunday the 10th are last week's.
        var monday = losAngeles
        monday.firstWeekday = 2
        log.add(entry("Sunday call", .joined, -5))
        let europe = try HomeModel(events: [], now: morning, calendar: monday, dailyLog: log)
        #expect(europe.weekLog(on: morning)?.hasPrefix("Tuesday") == true)
        let sundayStart = try HomeModel(events: [], now: morning, calendar: losAngeles, dailyLog: log)
        #expect(sundayStart.weekLog(on: morning)?.hasPrefix("Sunday") == true)
    }

    @Test("Block time saves the slot, records it, and moves the card on; Undo and Not now; a refused save records nothing")
    @MainActor func blockTime() throws {
        var written: [CalendarEvent] = []
        var removed: [String] = []
        var saved: [GoalRecords] = []
        let blocks = BlockWriter(add: { title, slot in
            let event = CalendarEvent(id: "block-\(written.count)", calendarID: "personal", title: title,
                                      start: slot.start, end: slot.end)
            written.append(event)
            return event
        }, remove: { removed.append($0) })
        // Friday 09:00: Personal time is free from 18:00, and again on Saturday.
        let goal = Goal(id: "book", title: "Write a book", window: .personal)
        let model = try HomeModel(events: [], now: morning, calendar: losAngeles,
                                  goals: GoalSettings(goals: [goal], offered: true), blocks: blocks,
                                  saveGoalRecords: { saved.append($0) })
        let card = try #require(model.goalCard)
        #expect(card.slot.start == morning.addingTimeInterval(9 * 3_600))

        let session = try model.blockTime(card)
        #expect(written.map(\.title) == ["Write a book"] && session.eventID == "block-0")
        // The block is busy at once, and the goal's next session goes to another day.
        #expect(try #require(model.goalCard).slot.start > losAngeles.startOfDay(for: morning).addingTimeInterval(86_400))
        #expect(saved.last?.sessions == [session])

        try model.undoBlock(session)
        #expect(removed == ["block-0"] && model.goalCard == card && saved.last == GoalRecords())

        model.notNow()
        #expect(model.goalCard == nil && saved.last?.lastNotNow == morning)

        // A refused save records nothing.
        var refusedSaves = 0
        let refusing = try HomeModel(events: [], now: morning, calendar: losAngeles,
                                     goals: GoalSettings(goals: [goal], offered: true),
                                     saveGoalRecords: { _ in refusedSaves += 1 })
        let offered = try #require(refusing.goalCard)
        #expect(throws: (any Error).self) { try refusing.blockTime(offered) }
        #expect(refusing.goalCard == offered && refusedSaves == 0)

        // An Undo the calendar refuses changes nothing: the block stays recorded and Home keeps its card, as the
        // event stays.
        struct Refused: Error {}
        var kept: [GoalRecords] = []
        let stuck = try HomeModel(events: [], now: morning, calendar: losAngeles,
                                  goals: GoalSettings(goals: [goal], offered: true),
                                  blocks: BlockWriter(add: { title, slot in
                                      CalendarEvent(id: "stuck", calendarID: "personal", title: title, start: slot.start,
                                                    end: slot.end)
                                  }, remove: { _ in throw Refused() }),
                                  saveGoalRecords: { kept.append($0) })
        let stuckSession = try stuck.blockTime(try #require(stuck.goalCard))
        let afterBlock = stuck.goalCard
        #expect(throws: Refused.self) { try stuck.undoBlock(stuckSession) }
        // A rebuild before the next fetch (here, restoring no Impacts) must still see the block and its event.
        stuck.restore([:])
        #expect(kept.last?.sessions == [stuckSession] && stuck.goalCard == afterBlock)
    }

    @Test("Home offers goal setup once, after the first Impact; Done keeps up to three goals with a title")
    @MainActor func goalSetup() throws {
        var saved: [GoalSettings] = []
        let review = meeting("review", at: morning.addingTimeInterval(600))
        let model = try HomeModel(events: [review], now: morning, calendar: losAngeles, saveGoals: { saved.append($0) })
        #expect(!model.offersGoalSetup)
        let card = try #require(model.snapshot.nextUp)
        _ = model.record(try #require(card.primaryAction), on: card)
        #expect(model.offersGoalSetup)
        model.goalSetupOffered()
        model.goalSetupOffered()
        #expect(!model.offersGoalSetup && saved == [GoalSettings(offered: true)])
        #expect(!model.canSaveGoals([Goal(id: "blank", title: "  ")]) && model.canSaveGoals([Goal(id: "a", title: "A")]))

        let goals = [" A ", "", "  ", "B", "C", "D"].enumerated().map { Goal(id: "\($0.offset)", title: $0.element) }
        let hours = WorkingHours(weekdays: [2], start: 480, end: 900)
        model.setGoals(goals, workingHours: hours)
        #expect(model.goals.goals.map(\.title) == ["A", "B", "C"] && model.goals.goals.map(\.id) == ["0", "3", "4"])
        #expect(model.goals.workingHours == hours && model.goals.offered && saved.last == model.goals)

        // A model built with goals, as after a relaunch, has no offer even with Impacts.
        let relaunched = try HomeModel(events: [review], now: morning, calendar: losAngeles,
                                       log: ActionLog(impacts: ["review": morning]), goals: model.goals)
        #expect(!relaunched.offersGoalSetup)

        // Done with every goal removed clears them.
        #expect(model.canSaveGoals([]))
        model.setGoals([], workingHours: hours)
        #expect(model.goals.goals.isEmpty && saved.last == model.goals)
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

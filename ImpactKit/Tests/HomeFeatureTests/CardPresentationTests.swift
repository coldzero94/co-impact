import Foundation
@testable import HomeFeature
import ImpactEngine
@testable import LiveSurfaces
import Testing
import UserNotifications

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()
private let sampleDate = losAngeles.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 12))!
private let clinic = Place(title: "Synthetic clinic", address: "1 Test Street", latitude: 37.5, longitude: 127)

/// A card from the real selection rules, so presentation sees what Home will see.
private func card(_ kind: CardKind, link: String? = nil, place: Place? = nil) throws -> ImpactCard {
    var event = CalendarEvent(id: "card", calendarID: "personal", title: "Card", start: start, end: start.addingTimeInterval(3_600))
    event.url = link.flatMap(URL.init(string:))
    event.structuredPlace = place
    let card = try #require(try ImpactEngine().card(for: event, now: start.addingTimeInterval(-3_600)))
    #expect(card.kind == kind)
    return card
}

@Suite struct CardPresentationTests {
    @Test("Providers are named from the meeting host", arguments: [
        ("https://zoom.us/j/1", "Zoom"), ("https://acme.zoom.us/j/1", "Zoom"), ("https://Zoom.us/j/1", "Zoom"),
        ("https://meet.google.com/abc-defg-hij", "Google Meet"),
        ("https://teams.microsoft.com/l/meetup-join/x", "Teams"), ("https://teams.live.com/meet/1", "Teams"),
        ("https://acme.webex.com/meet/x", "Webex"), ("https://facetime.apple.com/join#v=1", "FaceTime"),
    ])
    func provider(_ link: String, _ name: String) throws {
        #expect(try card(.onlineMeeting, link: link).provider == name)
    }

    @Test("Answer lines and key facts per card kind")
    func answers() throws {
        let online = try card(.onlineMeeting, link: "https://zoom.us/j/1")
        #expect(online.answer == "Zoom link ready")
        #expect(online.keyFact == "Zoom")
        let hybrid = try card(.hybrid, link: "https://teams.live.com/meet/1", place: clinic)
        #expect(hybrid.answer == "Teams link ready · Synthetic clinic")
        #expect(hybrid.keyFact == "Teams")
        let inPerson = try card(.inPerson, place: clinic)
        #expect(inPerson.answer == "1 Test Street")
        #expect(inPerson.keyFact == "Synthetic clinic")
        let noAddress = Place(title: "Synthetic park", latitude: 37.5, longitude: 127)
        #expect(try card(.inPerson, place: noAddress).answer == "Synthetic park")
    }

    /// `now` minus the start in seconds (negative is before the start), and the expected countdown.
    private static let countdowns: [(Double, Countdown)] = [
        (0, .now), (60, .now), (-1, .minutes(1)), (-690, .minutes(12)),
        (-3_540, .minutes(59)), (-3_541, .clock), (-3_600, .clock),
    ]

    @Test("Next up shows minutes under an hour, then the clock; Now from the start", arguments: countdowns)
    func countdown(_ nowOffset: Double, _ expected: Countdown) {
        #expect(Countdown(to: start, now: start.addingTimeInterval(nowOffset)) == expected)
    }

    @Test("The summary line agrees in number", arguments: [
        (3, 4, "3 of 4 events need you"), (1, 4, "1 of 4 events needs you"),
        (1, 1, "1 of 1 event needs you"), (0, 2, "0 of 2 events need you"), (0, 0, "No events left today"),
    ])
    func summary(_ cards: Int, _ left: Int, _ text: String) {
        #expect(summaryLine(cards: cards, eventsLeft: left) == text)
    }

    @Test("Attendees: up to three names in full, else the first two and a count", arguments: [
        (["Mina"], "Mina"), (["Mina", "Joon", "Sara"], "Mina, Joon, and Sara"),
        (["Mina", "Joon", "Sara", "Alex"], "Mina, Joon, and 2 others"),
        (["Mina", "Joon", "Sara", "Alex", "Dana"], "Mina, Joon, and 3 others"),
        (["", "Mina"], "Mina and Unnamed guest"), (["", "", "Joon", "Sara", "Alex"], "Joon, Sara, and 3 others"),
    ])
    func attendees(_ names: [String], _ line: String) {
        #expect(attendeeLine(names) == line)
    }

    @Test("Details read the engine's organizer, attendee, and notes facts")
    func details() throws {
        var event = CalendarEvent(id: "card", calendarID: "personal", title: "Card", start: start,
                                  end: start.addingTimeInterval(3_600), hasAttendees: true, isUserAttendee: true,
                                  url: URL(string: "https://zoom.us/j/1"),
                                  notes: "Agenda", organizer: "Mina Park", attendees: ["Joon Lee", "Sara Kim"])
        let card = try #require(try ImpactEngine().card(for: event, now: start.addingTimeInterval(-3_600)))
        #expect(card.organizer == "Mina Park" && card.attendees == ["Joon Lee", "Sara Kim"] && card.notes == "Agenda")
        event.notes = nil; event.organizer = nil; event.attendees = []
        let bare = try #require(try ImpactEngine().card(for: event, now: start.addingTimeInterval(-3_600)))
        #expect(bare.organizer == nil && bare.attendees.isEmpty && bare.notes == nil)
    }

    @Test("The fallback Now alert shows the card's title and answer, Time Sensitive, at the start of its Now phase")
    func fallbackAlert() throws {
        let zoom = try card(.onlineMeeting, link: "https://zoom.us/j/1")
        let live = try #require(LiveCard(zoom, runToken: "secret"))
        let now = live.nowPhase.lowerBound.addingTimeInterval(-3_600)
        let request = NowAlerts.request(for: live, now: now)
        #expect(request.identifier == NowAlerts.identifier(for: live) && request.identifier.hasPrefix(NowAlerts.prefix))
        // Moved to another time, the card's alert gets another identifier, so the old one is removed.
        let later = live.start.addingTimeInterval(3_600)
        let moved = LiveCard(cardID: live.cardID, title: live.title, answer: live.answer, symbol: live.symbol,
                             actionLabel: live.actionLabel, start: later,
                             nowPhase: later.addingTimeInterval(-600) ..< later.addingTimeInterval(600),
                             runToken: "secret", timeSensitive: true)
        #expect(NowAlerts.identifier(for: moved) != request.identifier)
        #expect(request.content.title == zoom.title && request.content.body == "Zoom link ready")
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(request.content.userInfo["card"] as? String == zoom.id)
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 3_600)
        // A focus block's alert comes at the default level (PRODUCT.md → Interruptions).
        var block = CalendarEvent(id: "block", calendarID: "personal", title: "Write a book", start: start,
                                  end: start.addingTimeInterval(3_600))
        block.focusGoal = "Write a book"
        let blockCard = try #require(try ImpactEngine().card(for: block, now: now))
        let focus = try #require(LiveCard(blockCard, runToken: "secret"))
        #expect(NowAlerts.request(for: focus, now: now).content.interruptionLevel == .active)
    }

    @Test("A Live Activity carries the card's title, answer, primary action, and Now phase")
    func liveCard() throws {
        let zoom = try card(.onlineMeeting, link: "https://zoom.us/j/1")
        let live = try #require(LiveCard(zoom, runToken: "secret"))
        #expect(live.cardID == zoom.id && live.title == zoom.title && live.answer == "Zoom link ready")
        #expect(live.symbol == "video.fill" && live.actionLabel == "Join meeting" && live.start == zoom.start)
        #expect(live.nowPhase == ImpactEngine.nowPhase(of: zoom))
        // The activity's own button carries the token, so it runs the card.
        #expect(LiveCard.cardID(fromRunURL: live.runURL, token: "secret") == zoom.id)
    }

    @Test("A run link names its card, whatever the ID holds, only with Impact's token", arguments: [
        "AD37F411-AFC9@1800000000/x?y=1&z", "a+b%20c d#e", "회의 🗓️",
    ])
    func runLink(_ id: String) throws {
        let link = LiveCard.runURL(cardID: id, token: "secret")
        #expect(LiveCard.cardID(fromRunURL: link, token: "secret") == id && LiveCard.isRunURL(link))
        #expect(LiveCard.cardID(fromRunURL: link, token: "guess") == nil)
        #expect(LiveCard.cardID(fromRunURL: link, token: "") == nil)
        let untokened = try #require(URL(string: "impact://run?card=x"))
        #expect(LiveCard.cardID(fromRunURL: untokened, token: "secret") == nil && LiveCard.isRunURL(untokened))
        #expect(LiveCard.cardID(fromRunURL: try #require(URL(string: "impact://open?card=x&token=secret")), token: "secret") == nil)
        #expect(LiveCard.cardID(fromRunURL: try #require(URL(string: "https://run?card=x&token=secret")), token: "secret") == nil)
        #expect(LiveCard.cardID(fromRunURL: try #require(URL(string: "impact://run?card=&token=secret")), token: "secret") == nil)
    }

    @Test("The run token is made once and kept")
    func runToken() throws {
        let suite = "impact-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = RunToken.load(defaults)
        #expect(!first.isEmpty && RunToken.load(defaults) == first)
        // An empty stored value would make every run link fail: it is replaced.
        defaults.set("", forKey: RunToken.key)
        #expect(!RunToken.load(defaults).isEmpty)
    }

    @Test("A Live Activity's card survives the encoding the system stores it in, and stays equal")
    func liveCardCodable() throws {
        let live = try #require(LiveCard(try card(.inPerson, place: clinic), runToken: "secret"))
        #expect(try JSONDecoder().decode(LiveCard.self, from: JSONEncoder().encode(live)) == live)
    }

    @Test("A sync requests only cards without an activity: at once inside their Now phase, else scheduled")
    func toRequest() throws {
        let online = try #require(LiveCard(try card(.onlineMeeting, link: "https://zoom.us/j/1"), runToken: "secret"))
        let visit = try #require(LiveCard(try card(.inPerson, place: clinic), runToken: "secret"))
        // Both cards start at `start`; their Now phase starts 10 minutes before.
        let early = LiveCard.toRequest(wanted: [online, visit], existing: [visit], now: start.addingTimeInterval(-3_600))
        #expect(early.startNow.isEmpty && early.schedule == [online])
        let inNow = LiveCard.toRequest(wanted: [online, visit], existing: [], now: start.addingTimeInterval(-600))
        #expect(inNow.startNow == [online, visit] && inNow.schedule.isEmpty)
    }

    @Test("Home wants Live Activities for the next two cards whose Now has not ended, and the first focus block")
    @MainActor func liveCards() throws {
        let model = try HomeFixtures.sample(at: 9.8, calendar: losAngeles, today: sampleDate)
        #expect(model.liveCards(runToken: "secret").map(\.cardID) == ["Design review", "Dentist", "Write a book"])
    }

    /// The states ImpactKit/AGENTS.md → UI documents for `-fixtureHour`, pinned so screenshots keep showing them.
    @Test("Sample day states", arguments: [9.8, 8, 15.4, 15.8, 19, 21])
    @MainActor func sampleDay(_ hour: Double) throws {
        let model = try HomeFixtures.sample(at: hour, calendar: losAngeles, today: sampleDate)
        let home = model.snapshot
        let countdown = home.nextUp.map { Countdown(to: $0.start, now: model.now) }
        switch hour {
        case 8:
            #expect(home.nextUp?.id == "1:1 with Mina" && countdown == .clock)
            #expect(home.doneCardIDs == ["Standup"])
        case 15.4:
            #expect(home.nextUp?.id == "Write a book" && home.nextUp?.kind == .focusBlock && countdown == .minutes(6))
            #expect(model.focus == nil)
        case 15.8:
            #expect(home.nextUp?.id == "Write a book" && model.focus?.start == model.now.addingTimeInterval(-18 * 60))
        case 19:
            #expect(home.nextUp == nil && home.laterToday.isEmpty)
            #expect(home.tomorrowMorning.map(\.id) == ["Client visit"] && home.next == nil)
        case 21:
            #expect(home.nextUp == nil && home.tomorrowMorning.isEmpty)
            #expect(home.next?.id == "Quarterly planning" && home.impactsToday == 2 && home.ringSegments == 2)
        default:
            #expect(home.nextUp?.id == "Design review" && countdown == .minutes(12))
            #expect(home.impactsToday == 2 && home.ringSegments == 6)
        }
    }

    @Test("Directions hours before an in-person card records nothing on Home")
    @MainActor func earlyPrimary() throws {
        let model = try HomeFixtures.sample(at: 9.8, calendar: losAngeles, today: sampleDate)
        let dentist = try #require(model.snapshot.laterToday.first { $0.id == "Dentist" })
        let directions = try #require(dentist.primaryAction)
        let before = model.snapshot
        let recorded = model.record(directions, on: dentist)
        #expect(!recorded && model.snapshot == before && !model.log.isDone(directions, on: dentist))
    }

    @Test("Running Next up's primary action records one Impact and promotes the next card")
    @MainActor func recordPrimary() throws {
        let model = try HomeFixtures.sample(at: 9.8, calendar: losAngeles, today: sampleDate)
        let review = try #require(model.snapshot.nextUp)
        #expect(review.id == "Design review" && model.snapshot.impactsToday == 2)
        let primary = try #require(review.primaryAction)
        let recorded = model.record(primary, on: review)
        let again = model.record(primary, on: review)
        #expect(recorded && !again)
        #expect(model.snapshot.nextUp?.id == "Dentist" && model.snapshot.doneCardIDs.contains("Design review"))
        #expect(model.snapshot.impactsToday == 3 && model.snapshot.ringSegments == 6)
    }

    @Test("A secondary action is marked done without an Impact")
    @MainActor func recordSecondary() throws {
        let model = try HomeFixtures.sample(at: 9.8, calendar: losAngeles, today: sampleDate)
        let townHall = try #require(model.snapshot.laterToday.first { $0.id == "Town hall" })
        let directions = try #require(townHall.confirmedActions.first { if case .directions = $0.kind { true } else { false } })
        #expect(!model.record(directions, on: townHall))
        #expect(model.log.isDone(directions, on: townHall) && model.snapshot.impactsToday == 2)
        #expect(!model.snapshot.doneCardIDs.contains("Town hall"))
    }

    @Test("Open link and its failure alert name a plain ASCII host, lowercased, without www; any other host gets the generic label")
    func linkLabel() throws {
        let figma = ActionKind.openLink(try #require(URL(string: "https://WWW.figma.com/file/x")))
        #expect(figma.label == "Open figma.com" && figma.failureTitle == "figma.com didn't open")
        #expect(try #require(URL(string: "https://www./doc")).shortHost == nil)
        #expect(try #require(URL(string: "https://paypaI.com/billing")).shortHost == "paypai.com")
        // A Cyrillic "а" (lookalike apple.com) and an encoded right-to-left override must never read as a real host.
        #expect(try #require(URL(string: "https://%E2%80%AEmoc.amgif/x")).shortHost == nil)
        #expect(ActionKind.openLink(try #require(URL(string: "https://\u{0430}pple.com/login"))).label == "Open link")
    }
}

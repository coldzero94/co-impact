import Foundation
@testable import HomeFeature
import ImpactEngine
import Testing

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

    /// The states ImpactKit/AGENTS.md → UI documents for `-fixtureHour`, pinned so screenshots keep showing them.
    @Test("Sample day states", arguments: [9.8, 8, 19])
    @MainActor func sampleDay(_ hour: Double) throws {
        let model = try HomeFixtures.sample(at: hour, calendar: losAngeles, today: sampleDate)
        let home = model.snapshot
        let countdown = home.nextUp.map { Countdown(to: $0.start, now: model.now) }
        switch hour {
        case 8:
            #expect(home.nextUp?.id == "1:1 with Mina" && countdown == .clock)
            #expect(home.doneCardIDs == ["Standup"])
        case 19:
            #expect(home.nextUp == nil && home.laterToday.isEmpty)
            #expect(home.tomorrowMorning.map(\.id) == ["Client visit"])
        default:
            #expect(home.nextUp?.id == "Design review" && countdown == .minutes(12))
            #expect(home.impactsToday == 2 && home.ringSegments == 5)
        }
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
        #expect(model.snapshot.impactsToday == 3 && model.snapshot.ringSegments == 5)
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

    @Test("Open link is labeled by host (PRODUCT.md → Action catalog)")
    func linkLabel() throws {
        let figma = ActionKind.openLink(try #require(URL(string: "https://WWW.figma.com/file/x")))
        #expect(figma.label == "Open figma.com" && figma.failureTitle == "figma.com didn't open")
    }
}

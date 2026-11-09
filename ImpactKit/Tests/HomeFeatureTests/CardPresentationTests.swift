import Foundation
@testable import HomeFeature
import ImpactEngine
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)
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
        ("https://zoom.us/j/1", "Zoom"), ("https://acme.zoom.us/j/1", "Zoom"),
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
        let inPerson = try card(.inPerson, place: clinic)
        #expect(inPerson.answer == "1 Test Street")
        #expect(inPerson.keyFact == "Synthetic clinic")
    }

    /// Seconds from the start to `now`, and the expected countdown.
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
}

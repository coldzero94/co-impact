import Foundation
import ImpactEngine
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let zoom = URL(string: "https://zoom.us/j/123")!
private let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/synthetic")!
private let place = Place(title: "Synthetic clinic", address: "110 Test Street", latitude: 37.5, longitude: 127)

private func event(_ edit: (inout CalendarEvent) -> Void = { _ in }) -> CalendarEvent {
    var event = CalendarEvent(
        id: "event-occurrence-1", calendarID: "personal", title: "Synthetic event",
        start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(7_200)
    )
    edit(&event)
    return event
}

private struct Example: Sendable, CustomTestStringConvertible {
    let event: CalendarEvent
    let kind: CardKind?
    var testDescription: String { event.title }
}

private let productExamples: [Example] = [
    Example(event: event { $0.title = "Design review"; $0.notes = "Join https://zoom.us/j/123" }, kind: .onlineMeeting),
    Example(event: event { $0.title = "1:1"; $0.location = "https://meet.google.com/abc-defg-hij" }, kind: .onlineMeeting),
    Example(event: event {
        $0.title = "Daily standup with Teams"; $0.seriesID = "daily"; $0.notes = teams.absoluteString
    }, kind: .onlineMeeting),
    Example(event: event { $0.title = "Daily standup without signal"; $0.seriesID = "daily" }, kind: nil),
    Example(event: event { $0.title = "Dentist"; $0.structuredPlace = place }, kind: .inPerson),
    Example(event: event { $0.title = "Lunch"; $0.location = "Café Onion Seongsu"; $0.geocodedPlace = place }, kind: .inPerson),
    Example(event: event { $0.title = "Team sync"; $0.location = "회의실 3A" }, kind: nil),
    Example(event: event {
        $0.title = "Town hall"; $0.location = "서울 중구 세종대로 110"; $0.geocodedPlace = place
        $0.notes = teams.absoluteString
    }, kind: .hybrid),
    Example(event: event { $0.title = "Holiday"; $0.isAllDay = true; $0.url = zoom }, kind: nil),
    Example(event: event { $0.title = "Declined meeting"; $0.participation = .declined; $0.url = zoom }, kind: nil),
    Example(event: event {
        $0.title = "Subscribed team event"; $0.calendarKind = .subscription; $0.hasAttendees = true; $0.url = zoom
    }, kind: nil),
    Example(event: event { $0.title = "Focus time" }, kind: nil),
    Example(event: event {
        $0.title = "Ended Zoom meeting"; $0.url = zoom
        $0.start = now.addingTimeInterval(-3_600); $0.end = now.addingTimeInterval(-300)
    }, kind: nil),
]

@Suite struct SelectionTests {
    private let engine: ImpactEngine

    init() throws { engine = try ImpactEngine() }

    @Test("All 13 PRODUCT.md examples", arguments: productExamples)
    private func productExample(_ example: Example) throws {
        let card = engine.card(for: example.event, now: now)
        #expect(card?.kind == example.kind)
        guard let kind = example.kind else { return }
        let selected = try #require(card)
        #expect(selected.id == example.event.id)
        #expect(selected.title == example.event.title)
        #expect(selected.start == example.event.start)
        #expect(selected.end == example.event.end)
        let primary = try #require(selected.actions.first)
        switch kind {
        case .onlineMeeting, .hybrid:
            guard case .joinMeeting = primary.kind else { Issue.record("Expected Join primary"); return }
        case .inPerson:
            #expect(primary.kind == .directions(to: place))
        }
        if kind == .hybrid { #expect(selected.actions[1].kind == .directions(to: place)) }
        #expect(selected.facts.allSatisfy {
            if case .inferred = $0.provenance { return false }
            return true
        })
    }

    @Test("Provider allowlist works in every event field", arguments: [
        "https://zoom.us/j/123?pwd=synthetic", "https://us02web.zoom.us/my/synthetic", "https://zoom.us/w/123",
        "https://meet.google.com/abc-defg-hij", "https://teams.microsoft.com/l/meetup-join/synthetic",
        "https://teams.live.com/meet/123", "https://example.webex.com/meet/synthetic",
        "https://example.webex.com/join/synthetic", "https://example.webex.com/example/j.php?MTID=synthetic",
        "https://facetime.apple.com/join#v=1", "https://ZOOM.US/j/123",
    ], ["url", "location", "notes"])
    func meetingProviders(_ link: String, _ field: String) throws {
        let input = event {
            switch field {
            case "url": $0.url = URL(string: link)
            case "location": $0.location = link
            default: $0.notes = "📅 회의 링크: (\(link))."
            }
        }
        let card = try #require(engine.card(for: input, now: now))
        #expect(card.kind == .onlineMeeting)
        #expect(card.actions.first?.kind == .joinMeeting(URL(string: link)!))
        #expect(card.actions.first?.provenance == .calendar(field: field))
        #expect(card.facts.last?.provenance == .calendar(field: field))
    }

    @Test("Unrecognized hosts, paths and schemes never create a meeting", arguments: [
        "https://zoom.us.evil.example/j/123", "https://notzoom.us/j/123", "https://zoom.us/", "https://zoom.us/j/",
        "https://zoom.us/junk/123", "https://meet.google.com/", "https://meet.google.com/about",
        "https://evil.meet.google.com/abc-defg-hij", "https://teams.microsoft.com/l/meetup-join-evil/123",
        "https://teams.live.com/meeting/123", "https://webex.com/meet/123", "https://evilwebex.com/meet/123",
        "https://example.webex.com/about", "https://facetime.apple.com/join-evil", "ftp://zoom.us/j/123",
        "javascript://zoom.us/j/123", "https://user:password@zoom.us/j/123",
    ])
    func invalidMeetingURLs(_ link: String) {
        #expect(engine.card(for: event { $0.url = URL(string: link) }, now: now) == nil)
    }

    @Test("Each exclusion overrides a confirmed signal", arguments: [
        "all-day", "canceled", "declined", "ended", "ends-now", "invalid-dates", "other-attendees", "subscription", "birthdays",
    ])
    func exclusions(_ exclusion: String) {
        let input = event {
            $0.url = zoom
            switch exclusion {
            case "all-day": $0.isAllDay = true
            case "canceled": $0.isCanceled = true
            case "declined": $0.participation = .declined
            case "ended": $0.start = now.addingTimeInterval(-100); $0.end = now.addingTimeInterval(-1)
            case "ends-now": $0.start = now.addingTimeInterval(-100); $0.end = now
            case "invalid-dates": $0.end = $0.start
            case "other-attendees": $0.hasAttendees = true
            case "subscription": $0.calendarKind = .subscription
            default: $0.calendarKind = .birthdays
            }
        }
        #expect(engine.card(for: input, now: now) == nil)
    }

    @Test("Organizer, attendee and personal ongoing events qualify", arguments: ["organizer", "attendee", "personal"])
    func ownEvents(_ role: String) {
        let input = event {
            $0.url = zoom; $0.start = now.addingTimeInterval(-600)
            $0.hasAttendees = role != "personal"
            $0.isUserOrganizer = role == "organizer"; $0.isUserAttendee = role == "attendee"
        }
        #expect(engine.card(for: input, now: now)?.kind == .onlineMeeting)
    }

    @Test("Calendar opt-in removes only the calendar-type exclusion", arguments: [CalendarKind.subscription, .birthdays])
    func calendarOptIn(_ kind: CalendarKind) {
        var input = event { $0.calendarKind = kind; $0.url = zoom }
        #expect(engine.card(for: input, now: now, includedCalendarIDs: [input.calendarID]) != nil)
        #expect(engine.card(for: input, now: now, includedCalendarIDs: ["another-calendar"]) == nil)
        input.hasAttendees = true
        #expect(engine.card(for: input, now: now, includedCalendarIDs: [input.calendarID]) == nil)
    }

    @Test("Suppression matches series or exact title on the same calendar")
    func suppression() {
        let input = event { $0.url = zoom; $0.seriesID = "daily" }
        for rule in [SuppressionRule.series(calendarID: input.calendarID, seriesID: "daily"),
                     .title(calendarID: input.calendarID, title: input.title)] {
            #expect(engine.card(for: input, now: now, suppressionRules: [rule]) == nil)
            var otherCalendar = input
            otherCalendar.calendarID = "other"
            #expect(engine.card(for: otherCalendar, now: now, suppressionRules: [rule]) != nil)
        }
        #expect(engine.card(for: input, now: now, suppressionRules: [.series(calendarID: input.calendarID, seriesID: "other")]) != nil)
        #expect(engine.card(for: input, now: now, suppressionRules: [.title(calendarID: input.calendarID, title: "other")]) != nil)
    }

    @Test("Room labels, empty strings and URLs are not geocoding candidates", arguments: [
        "", " \n ", "회의실 3A", "Room 301", "Conference room", "Conf A", "3F", "F12", "12th floor", "3층",
        "https://example.com/office", "meet.google.com/abc-defg-hij", "mailto:office@example.com",
    ])
    func notPhysicalDestinations(_ location: String) {
        #expect(!engine.canGeocode(location))
        #expect(engine.card(for: event { $0.location = location; $0.geocodedPlace = place }, now: now) == nil)
    }

    @Test("Unresolved locations do not create cards", arguments: [
        "Café Onion Seongsu", "서울 중구 세종대로 110", "1100 F Street NW",
    ])
    func unresolvedPlace(_ location: String) {
        #expect(engine.canGeocode(location))
        #expect(engine.card(for: event { $0.location = location }, now: now) == nil)
    }

    @Test("Structured coordinates take precedence, including for room labels")
    func placeProvenance() throws {
        let structured = try #require(engine.card(for: event {
            $0.location = "회의실 3A"; $0.structuredPlace = place
            $0.geocodedPlace = Place(title: "Other", latitude: 0, longitude: 0)
        }, now: now))
        #expect(structured.actions.first?.kind == .directions(to: place))
        #expect(structured.actions.first?.provenance == .calendar(field: "structuredLocation"))
        #expect(structured.facts.last?.provenance == .calendar(field: "structuredLocation"))
        let computed = try #require(engine.card(for: event { $0.location = "110 Test Street"; $0.geocodedPlace = place }, now: now))
        #expect(computed.actions.first?.provenance == .computed(by: "geocoding"))
        #expect(computed.facts.last?.provenance == .computed(by: "geocoding"))
        #expect(engine.canGeocode(nil) == false)
        #expect(engine.card(for: event { $0.geocodedPlace = place }, now: now) == nil)
    }

    @Test("Invalid coordinates cannot create a destination", arguments: [
        Place(title: "Bad", latitude: 91, longitude: 0), Place(title: "Bad", latitude: 0, longitude: -181),
        Place(title: "Bad", latitude: .nan, longitude: 0), Place(title: "Bad", latitude: 0, longitude: .infinity),
    ])
    func invalidCoordinates(_ invalid: Place) {
        #expect(engine.card(for: event { $0.structuredPlace = invalid }, now: now) == nil)
        #expect(engine.card(for: event { $0.location = "110 Test Street"; $0.geocodedPlace = invalid }, now: now) == nil)
    }

    @Test("Only notes supply linked documents; actions are unique and grounded")
    func secondaryActions() throws {
        let document = URL(string: "https://www.figma.com/file/synthetic")!
        let card = try #require(engine.card(for: event {
            $0.url = zoom; $0.structuredPlace = place
            $0.notes = "\(teams) \(document) \(document) mailto:test@example.com tel:+12025550123"
        }, now: now))
        #expect(card.kind == .hybrid)
        #expect(card.actions.map(\.kind) == [.joinMeeting(zoom), .directions(to: place), .openLink(document)])
        #expect(card.actions.last?.provenance == .calendar(field: "notes"))
        #expect(engine.card(for: event { $0.notes = document.absoluteString }, now: now) == nil)
        let noDocuments = try #require(engine.card(for: event { $0.url = document; $0.structuredPlace = place }, now: now))
        #expect(noDocuments.actions.count == 1)
    }

    @Test("Calls come from location and notes only for in-person cards")
    func calls() throws {
        let card = try #require(engine.card(for: event {
            $0.structuredPlace = place; $0.location = "+1 (202) 555-0123"; $0.notes = "Call +1 (202) 555-0123"
        }, now: now))
        #expect(card.actions.count == 2)
        let call = try #require(card.actions.last)
        guard case let .call(number) = call.kind else { Issue.record("Expected Call"); return }
        #expect(number.filter(\.isNumber) == "12025550123")
        #expect(call.provenance == .calendar(field: "location"))
        #expect(engine.card(for: event { $0.notes = "Call +1 (202) 555-0123" }, now: now) == nil)
        let online = try #require(engine.card(for: event { $0.url = zoom; $0.notes = "Call +1 (202) 555-0123" }, now: now))
        #expect(online.actions.count == 1)
        let notesOnly = try #require(engine.card(for: event {
            $0.structuredPlace = place; $0.notes = "Call +1 (202) 555-0123"
        }, now: now))
        #expect(notesOnly.actions.last?.provenance == .calendar(field: "notes"))
        #expect(notesOnly.actions.last?.kind == call.kind)
    }

    @Test("Call dials the number before an extension or pause; lettered numbers get no URL", arguments: [
        ("02-555-0100", "tel:025550100"), ("+82 2 555 0100", "tel:+8225550100"), ("555-0100;23", "tel:5550100"),
        ("+1 555 010 0199,,123456#", "tel:+15550100199"), ("1-800-FLOWERS", nil), ("ext", nil),
    ] as [(String, String?)])
    func telURL(_ number: String, _ url: String?) {
        #expect(ImpactEngine.telURL(number)?.absoluteString == url)
    }

    /// Notes text through the real detector, and the number Call dials (nil: no Call action).
    @Test("Call actions dial what the detector found, without extensions", arguments: [
        ("Reception 02-555-0100 내선 3", "tel:025550100"), ("Desk (555) 010-0199 ext. 23", "tel:5550100199"),
        ("Order at 1-800-FLOWERS", nil),
    ] as [(String, String?)])
    func detectedCalls(_ notes: String, _ url: String?) throws {
        let card = try #require(engine.card(for: event { $0.structuredPlace = place; $0.notes = notes }, now: now))
        let number = card.actions.lazy.compactMap { if case .call(let number) = $0.kind { number } else { nil } }.first
        #expect(number.flatMap(ImpactEngine.telURL)?.absoluteString == url)
    }

    @Test("Meeting fields have stable priority and invalid links do not hide later matches")
    func meetingPriority() throws {
        var input = event {
            $0.url = zoom; $0.location = teams.absoluteString
            $0.notes = "https://meet.google.com/abc-defg-hij"
        }
        #expect(engine.card(for: input, now: now)?.actions.first?.kind == .joinMeeting(zoom))
        input.url = URL(string: "https://example.com/unrelated")
        let card = try #require(engine.card(for: input, now: now))
        #expect(card.actions.first?.kind == .joinMeeting(teams))
        #expect(card.actions.first?.provenance == .calendar(field: "location"))
    }

    @Test("Recurring occurrences keep separate card identities and share a suppression rule")
    func recurringIdentities() throws {
        let first = event { $0.seriesID = "daily"; $0.url = zoom }
        var second = first
        second.id = "event-occurrence-2"
        second.start = first.start.addingTimeInterval(86_400)
        second.end = first.end.addingTimeInterval(86_400)
        let firstCard = try #require(engine.card(for: first, now: now))
        let secondCard = try #require(engine.card(for: second, now: now))
        #expect(firstCard.id != secondCard.id)
        let rules = [SuppressionRule.series(calendarID: first.calendarID, seriesID: "daily")]
        #expect(engine.card(for: first, now: now, suppressionRules: rules) == nil)
        #expect(engine.card(for: second, now: now, suppressionRules: rules) == nil)
    }
}

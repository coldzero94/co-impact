@testable import CalendarSources
import CoreLocation
import EventKit
import Foundation
import ImpactEngine
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)

/// An unsaved event: building one needs no calendar access, so no test reads the machine's calendar.
private func event(_ edit: (EKEvent) -> Void = { _ in }) -> EKEvent {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = "Design review"
    event.startDate = start
    event.endDate = start.addingTimeInterval(3_600)
    edit(event)
    return event
}

private func structured(_ title: String?, at coordinate: (Double, Double)? = (37.544, 127.056)) -> EKStructuredLocation {
    let location = EKStructuredLocation()
    location.title = title
    location.geoLocation = coordinate.map { CLLocation(latitude: $0.0, longitude: $0.1) }
    return location
}

@Suite struct EventMappingTests {
    @Test("Fields carry over; an unsaved event on no calendar is regular, with no attendees and unknown participation")
    func fields() throws {
        let zoom = try #require(URL(string: "https://zoom.us/j/1"))
        let mapped = CalendarEvent(event {
            $0.location = "Room 3"; $0.url = zoom; $0.notes = "Agenda"; $0.isAllDay = false
        })
        #expect(mapped.title == "Design review" && mapped.start == start && mapped.end == start.addingTimeInterval(3_600))
        #expect(mapped.location == "Room 3" && mapped.url == zoom && mapped.notes == "Agenda")
        #expect(mapped.calendarKind == .regular && mapped.participation == .unknown && !mapped.isCanceled)
        #expect(!mapped.hasAttendees && !mapped.isUserAttendee && !mapped.isUserOrganizer && mapped.seriesID == nil)
        #expect(CalendarEvent(event { $0.isAllDay = true }).isAllDay)
        #expect(CalendarEvent(event { $0.title = "  " }).title == "")
    }

    @Test("A single event's ID is its item ID; a recurring occurrence's adds its date and names its series")
    func mappedIDs() {
        let single = event()
        let mapped = CalendarEvent(single)
        #expect(mapped.id == single.calendarItemIdentifier && mapped.seriesID == nil && mapped.calendarID == "")
        let daily = event { $0.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)) }
        let occurrence = CalendarEvent(daily)
        #expect(occurrence.id == "\(daily.calendarItemIdentifier)@1800000000")
        #expect(occurrence.seriesID == daily.calendarItemIdentifier)
    }

    @Test("Calendar kinds: subscribed CalDAV calendars and Birthdays are not the user's own", arguments: [
        (EKCalendarType.local, false, CalendarKind.regular), (.calDAV, false, .regular), (.exchange, false, .regular),
        (.calDAV, true, .subscription), (.subscription, false, .subscription), (.birthday, false, .birthdays),
    ])
    func kinds(_ type: EKCalendarType, _ subscribed: Bool, _ kind: CalendarKind) {
        #expect(EventKitCalendar.kind(type: type, isSubscribed: subscribed) == kind)
    }

    @Test("Participation keeps accepted, declined, and tentative; anything else is unknown")
    func participation() {
        #expect(CalendarEvent.participation(.accepted) == .accepted)
        #expect(CalendarEvent.participation(.declined) == .declined)
        #expect(CalendarEvent.participation(.tentative) == .tentative)
        for other: EKParticipantStatus? in [.pending, .delegated, .completed, .inProcess, .unknown, nil] {
            #expect(CalendarEvent.participation(other) == .unknown)
        }
    }

    @Test("Only full access reads; restricted is told apart from denied and write-only")
    func access() {
        #expect(CalendarAccess(.fullAccess) == .granted && CalendarAccess(.notDetermined) == .notDetermined)
        #expect(CalendarAccess(.denied) == .denied && CalendarAccess(.writeOnly) == .denied)
        #expect(CalendarAccess(.restricted) == .restricted)
    }

    @Test("A single event keeps its item ID; a recurring occurrence adds its original date")
    func occurrenceIDs() {
        #expect(CalendarEvent.occurrenceID(item: "A", occurrence: nil, recurring: false) == "A")
        #expect(CalendarEvent.occurrenceID(item: "A", occurrence: start, recurring: false) == "A")
        #expect(CalendarEvent.occurrenceID(item: "A", occurrence: start, recurring: true) == "A@1800000000")
        #expect(CalendarEvent.occurrenceID(item: "A", occurrence: nil, recurring: true) == "A")
    }

    @Test("A structured location names the place from its first line and the address from the rest")
    func places() throws {
        let multiline = try #require(Place(structured("Seongsu Dental\n12 Synthetic-ro\nSeoul"), location: nil))
        #expect(multiline.title == "Seongsu Dental" && multiline.address == "12 Synthetic-ro, Seoul")
        #expect(multiline.latitude == 37.544 && multiline.longitude == 127.056)

        let fromLocation = try #require(Place(structured("City Hall"), location: "City Hall\n110 Sejong-daero"))
        #expect(fromLocation.title == "City Hall" && fromLocation.address == "110 Sejong-daero")

        let untitled = try #require(Place(structured(" "), location: "Clinic\n1 Test Street"))
        #expect(untitled.title == "Clinic" && untitled.address == "1 Test Street")

        #expect(Place(structured("Somewhere else"), location: "Clinic\n1 Test Street")?.address == nil)
        #expect(Place(structured(nil), location: nil) == nil)
        #expect(Place(structured("No coordinates", at: nil), location: nil) == nil)
    }

    @Test("A mapped structured location lets selection make an in-person card")
    func inPersonCard() throws {
        let mapped = CalendarEvent(event { $0.structuredLocation = structured("Seongsu Dental\n12 Synthetic-ro") })
        let place = try #require(mapped.structuredPlace)
        let card = try #require(try ImpactEngine().card(for: mapped, now: start.addingTimeInterval(-3_600)))
        #expect(card.kind == .inPerson && card.primaryAction?.kind == .directions(to: place))
    }
}

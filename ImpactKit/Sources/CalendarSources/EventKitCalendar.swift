import EventKit
import Foundation
import ImpactEngine

/// Whether Impact may read the calendar (PRODUCT.md → Permissions). Only full access reads events.
public enum CalendarAccess: Sendable {
    case notDetermined, granted, denied

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied // denied, restricted, write-only
        }
    }
}

/// The user's calendar through EventKit: the fetch and normalize steps of ARCHITECTURE.md → Pipeline.
@MainActor
public final class EventKitCalendar {
    /// Posted when the store changes outside the app; events fetched before it may be stale.
    public static let changed = Notification.Name.EKEventStoreChanged

    private let store = EKEventStore()

    public init() {}

    public static var access: CalendarAccess { CalendarAccess(EKEventStore.authorizationStatus(for: .event)) }

    /// Asks for full access; the system prompts only the first time, later calls return the current answer.
    public func requestAccess() async throws -> CalendarAccess {
        _ = try await store.requestFullAccessToEvents()
        return Self.access
    }

    /// Occurrences overlapping `start..<end`, recurring events expanded.
    public func events(from start: Date, to end: Date) -> [CalendarEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .map(CalendarEvent.init)
    }
}

extension CalendarEvent {
    /// Normalizes one EventKit occurrence (ARCHITECTURE.md → Engine model and selection).
    /// shortcut: no geocoding, so a typed address without a structured location gives no in-person card yet.
    init(_ event: EKEvent) {
        let me = event.attendees?.first { $0.isCurrentUser }
        let kind: CalendarKind = switch event.calendar?.type {
        case .subscription: .subscription
        case .birthday: .birthdays
        default: .regular
        }
        let participation: Participation = switch me?.participantStatus {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        default: .unknown
        }
        self.init(
            id: Self.occurrenceID(item: event.calendarItemIdentifier, occurrence: event.occurrenceDate as Date?,
                                  recurring: event.hasRecurrenceRules),
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate, end: event.endDate,
            calendarKind: kind, isAllDay: event.isAllDay, isCanceled: event.status == .canceled,
            participation: participation,
            hasAttendees: event.hasAttendees,
            isUserOrganizer: event.organizer?.isCurrentUser ?? false,
            isUserAttendee: me != nil,
            seriesID: event.hasRecurrenceRules ? event.calendarItemIdentifier : nil,
            location: event.location, url: event.url, notes: event.notes,
            structuredPlace: event.structuredLocation.flatMap { Place($0, location: event.location) }
        )
    }

    /// One ID per occurrence: a recurring series shares its item ID, so its occurrences add their original
    /// date.
    /// shortcut: the item ID changes after a full sync, and a moved occurrence gets an item ID of its own with
    /// no recurrence rules (ARCHITECTURE.md → Platform facts), so after either a done card shows as not done
    /// again, and a moved occurrence is not part of its series' ID.
    static func occurrenceID(item: String, occurrence: Date?, recurring: Bool) -> String {
        guard recurring, let occurrence else { return item }
        return "\(item)@\(Int(occurrence.timeIntervalSince1970))"
    }
}

extension Place {
    /// A structured location with coordinates. Its title's first line names the place, and the rest is the
    /// address, else the event's location lines after that name. No name means no place.
    init?(_ structured: EKStructuredLocation, location: String?) {
        guard let coordinate = structured.geoLocation?.coordinate else { return nil }
        let lines = { (text: String?) in
            (text ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let titleLines = lines(structured.title)
        let locationLines = lines(location)
        guard let name = titleLines.first ?? locationLines.first else { return nil }
        let rest = titleLines.count > 1 ? titleLines.dropFirst()
            : locationLines.first == name ? locationLines.dropFirst() : []
        self.init(title: name, address: rest.isEmpty ? nil : rest.joined(separator: ", "),
                  latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

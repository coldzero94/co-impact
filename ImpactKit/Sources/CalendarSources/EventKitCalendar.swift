import EventKit
import Foundation
import ImpactEngine

/// Whether Impact may read the calendar (PRODUCT.md → Permissions). Only full access reads events.
public enum CalendarAccess: Sendable {
    case notDetermined, granted
    /// Denied or write-only: the user can grant full access in Settings.
    case denied
    /// Restricted by the device's management or Screen Time: the user cannot change it (hard rule 8).
    case restricted

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .writeOnly: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

/// The user's calendar through EventKit: the fetch and normalize steps of ARCHITECTURE.md → Pipeline.
@MainActor
public final class EventKitCalendar {
    /// Posted whenever the calendar database changes: other apps, this app's own saves, or a change of
    /// access. Events fetched before it may be stale.
    public static let changed = Notification.Name.EKEventStoreChanged

    private let store = EKEventStore()

    public init() {}

    public static var access: CalendarAccess { CalendarAccess(EKEventStore.authorizationStatus(for: .event)) }

    /// Asks for full access; the system prompts only the first time, later calls return the current answer.
    public func requestAccess() async throws -> CalendarAccess {
        _ = try await store.requestFullAccessToEvents()
        return Self.access
    }

    /// Occurrences in the range, recurring events expanded; nil without full access or without a calendar
    /// Impact reads, so an empty result always means an empty range, never an unread one (hard rule 2).
    public func events(from start: Date, to end: Date) -> [CalendarEvent]? {
        guard Self.access == .granted,
              store.calendars(for: .event).contains(where: { Self.kind($0) == .regular }) else { return nil }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .map(CalendarEvent.init)
    }

    /// Subscription and Birthdays calendars are not the user's own (PRODUCT.md → Exclusions, D12). A
    /// subscription synced through iCloud is a CalDAV calendar marked subscribed.
    nonisolated static func kind(_ calendar: EKCalendar?) -> CalendarKind {
        kind(type: calendar?.type, isSubscribed: calendar?.isSubscribed ?? false)
    }

    nonisolated static func kind(type: EKCalendarType?, isSubscribed: Bool) -> CalendarKind {
        switch type {
        case .birthday: .birthdays
        case .subscription: .subscription
        default: isSubscribed ? .subscription : .regular
        }
    }
}

extension CalendarEvent {
    /// Normalizes one EventKit occurrence (ARCHITECTURE.md → Engine model and selection).
    /// shortcut: places need coordinates and nothing geocodes yet, so a location without them (typed, or
    /// synced as text) gives no in-person card; fill `geocodedPlace` once the owner settles geocoding.
    init(_ event: EKEvent) {
        let me = event.attendees?.first { $0.isCurrentUser }
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            // A moved occurrence is detached; some servers may keep the series' item ID for it.
            id: Self.occurrenceID(item: event.calendarItemIdentifier, occurrence: event.occurrenceDate as Date?,
                                  recurring: event.hasRecurrenceRules || event.isDetached),
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: title.isEmpty ? "Untitled" : title,
            start: event.startDate, end: event.endDate,
            calendarKind: EventKitCalendar.kind(event.calendar),
            isAllDay: event.isAllDay, isCanceled: event.status == .canceled,
            participation: Self.participation(me?.participantStatus),
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
    /// shortcut: the item ID changes after a full sync, and on a local calendar a moved occurrence gets an item
    /// ID of its own with no series ID (ARCHITECTURE.md → Platform facts). Either way the occurrence becomes a
    /// new card: a done one shows as not done again (its old Impact still counts today, so acting again counts
    /// twice), and muting its series misses a moved one. Revisit with `calendarItemExternalIdentifier` before
    /// dismissals rely on series IDs.
    static func occurrenceID(item: String, occurrence: Date?, recurring: Bool) -> String {
        guard recurring, let occurrence else { return item }
        return "\(item)@\(Int(occurrence.timeIntervalSince1970))"
    }

    /// The user's answer to an invitation; anything but accepted, declined, or tentative is unknown.
    static func participation(_ status: EKParticipantStatus?) -> Participation {
        switch status {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        default: .unknown
        }
    }
}

extension Place {
    /// A structured location with coordinates. Its title's first line names the place (or, with no title, the
    /// location text's first line), and the rest is the address, else the location text's lines after that
    /// name. No name means no place.
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

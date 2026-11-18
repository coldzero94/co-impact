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

public enum BlockError: Error {
    /// No default calendar for new events, or one Impact may not write to.
    case noWritableCalendar
}

/// The user's calendar through EventKit: the fetch and normalize steps of ARCHITECTURE.md → Pipeline, and Block time.
@MainActor
public final class EventKitCalendar {
    /// Posted whenever the calendar database changes: other processes (including account syncs), this app's
    /// own saves, or a change of access. Events fetched before it may be stale.
    public static let changed = Notification.Name.EKEventStoreChanged

    private let store = EKEventStore()

    public init() {}

    public static var access: CalendarAccess { CalendarAccess(EKEventStore.authorizationStatus(for: .event)) }

    /// Asks for full access; the system prompts only the first time, later calls return the current answer.
    public func requestAccess() async throws -> CalendarAccess {
        _ = try await store.requestFullAccessToEvents()
        return Self.access
    }

    /// Occurrences in the range, recurring events expanded; nil without full access or without a regular
    /// calendar, so callers never mistake an unread calendar for an empty day (hard rule 2).
    /// shortcut: checks regular calendars only; count opted-in calendars too once `includedCalendarIDs` has a
    /// setting (D12).
    public func events(from start: Date, to end: Date) -> [CalendarEvent]? {
        guard Self.access == .granted,
              store.calendars(for: .event).contains(where: { Self.kind($0) == .regular }) else { return nil }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .map(CalendarEvent.init)
    }

    /// Block time (PRODUCT.md → Block time): saves an event titled with the goal, without attendees or alarms, to the
    /// default calendar for new events, and returns it as Home will fetch it.
    /// shortcut: with no writable default calendar this throws, and Home says so; let the user pick a writable calendar
    /// once (PRODUCT.md) if that happens on devices.
    public func addBlock(title: String, during slot: DateInterval) throws -> CalendarEvent {
        guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw BlockError.noWritableCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = slot.start
        event.endDate = slot.end
        event.alarms = nil
        try store.save(event, span: .thisEvent, commit: true)
        return CalendarEvent(event)
    }

    /// Undo after Block time: removes the event Impact just created, by its item ID. Never call it for another event
    /// (hard rule 8, PRODUCT.md → Block time). An event already gone is not an error.
    public func removeBlock(eventID: String) throws {
        guard let event = store.calendarItem(withIdentifier: eventID) as? EKEvent else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// Subscription and Birthdays calendars are not the user's own (PRODUCT.md → Exclusions, D12). A CalDAV
    /// subscription (e.g. on iCloud) has type CalDAV and is marked subscribed.
    /// Calendars of a delegated account (`EKSource.isDelegate`) count as the user's own (owner, D12).
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
    /// shortcut: places need coordinates and nothing geocodes yet, so a location without them (typed, or synced
    /// as text) gives no in-person card. Apple's geocoder gave wrong or no places in a simulator check (Platform
    /// facts); fill `geocodedPlace` (for locations `canGeocode` accepts) once the device check passes
    /// (ROADMAP.md, step 10).
    init(_ event: EKEvent) {
        let me = event.attendees?.first { $0.isCurrentUser }
        let organizer = event.organizer
        self.init(
            // A moved occurrence gets its own item ID on a local calendar (Platform facts); the date keeps IDs
            // unique for other detached occurrences, or if a server keeps the series' item ID (unverified).
            id: Self.occurrenceID(item: event.calendarItemIdentifier, occurrence: event.occurrenceDate as Date?,
                                  recurring: event.hasRecurrenceRules || event.isDetached),
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            start: event.startDate, end: event.endDate,
            calendarKind: EventKitCalendar.kind(event.calendar),
            isAllDay: event.isAllDay, isCanceled: event.status == .canceled, isFree: event.availability == .free,
            participation: Self.participation(me?.participantStatus),
            hasAttendees: event.hasAttendees,
            isUserOrganizer: organizer?.isCurrentUser ?? false,
            isUserAttendee: me != nil,
            seriesID: event.hasRecurrenceRules ? event.calendarItemIdentifier : nil,
            location: event.location, url: event.url, notes: event.notes,
            organizer: organizer.flatMap {
                Self.organizerName(isCurrentUser: $0.isCurrentUser, name: $0.name, url: $0.url)
            },
            attendees: (event.attendees ?? [])
                .filter {
                    Self.isOtherPerson(type: $0.participantType, isCurrentUser: $0.isCurrentUser, url: $0.url,
                                       organizer: organizer?.url)
                }
                .map { Self.displayName(name: $0.name, url: $0.url) },
            structuredPlace: event.structuredLocation.flatMap { Place($0, location: event.location) }
        )
    }

    /// One ID per occurrence: a recurring series shares its item ID, so its occurrences add their original
    /// date.
    /// shortcut: the item ID changes after a full sync, and on a local calendar a moved occurrence gets an item
    /// ID of its own with no series ID (ARCHITECTURE.md → Platform facts). Either way the occurrence becomes a
    /// new card: a done one shows as not done again (its old Impact still counts today, so acting again counts
    /// twice), and muting its series misses a moved one (see `Dismissals.mute`).
    static func occurrenceID(item: String, occurrence: Date?, recurring: Bool) -> String {
        guard recurring, let occurrence else { return item }
        return "\(item)@\(Int(occurrence.timeIntervalSince1970))"
    }

    /// Whether card detail lists this attendee: not the user, a room, or equipment, and not the organizer again
    /// (same address in any letter case, as calendar addresses compare).
    static func isOtherPerson(type: EKParticipantType, isCurrentUser: Bool, url: URL, organizer: URL?) -> Bool {
        !isCurrentUser && ![.room, .resource].contains(type)
            && url.absoluteString.lowercased() != organizer?.absoluteString.lowercased()
    }

    /// The organizer card detail names: nobody when it is the user.
    static func organizerName(isCurrentUser: Bool, name: String?, url: URL) -> String? {
        isCurrentUser ? nil : displayName(name: name, url: url)
    }

    /// A participant's name, else their email address (decoded, without `mailto:`); empty with neither, which card
    /// detail shows as an unnamed guest rather than a bare identifier.
    static func displayName(name: String?, url: URL) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        guard url.scheme?.lowercased() == "mailto" else { return "" }
        let address = url.absoluteString.dropFirst("mailto:".count)
        return (address.removingPercentEncoding ?? String(address)).trimmingCharacters(in: .whitespacesAndNewlines)
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

import Foundation

public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// A source identifier plus occurrence start, so recurring occurrences stay distinct.
    public var id: String
    public var calendarID: String
    public var calendarKind: CalendarKind
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCanceled: Bool
    public var participation: Participation
    public var hasAttendees: Bool
    public var isUserOrganizer: Bool
    public var isUserAttendee: Bool
    public var seriesID: String?
    public var location: String?
    public var url: URL?
    public var notes: String?
    public var structuredPlace: Place?
    /// A successful address/POI lookup for this event's location, supplied by the caller.
    public var geocodedPlace: Place?

    public init(
        id: String, calendarID: String, title: String, start: Date, end: Date,
        calendarKind: CalendarKind = .regular, isAllDay: Bool = false, isCanceled: Bool = false,
        participation: Participation = .unknown, hasAttendees: Bool = false,
        isUserOrganizer: Bool = false, isUserAttendee: Bool = false, seriesID: String? = nil,
        location: String? = nil, url: URL? = nil, notes: String? = nil,
        structuredPlace: Place? = nil, geocodedPlace: Place? = nil
    ) {
        self.id = id
        self.calendarID = calendarID
        self.calendarKind = calendarKind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCanceled = isCanceled
        self.participation = participation
        self.hasAttendees = hasAttendees
        self.isUserOrganizer = isUserOrganizer
        self.isUserAttendee = isUserAttendee
        self.seriesID = seriesID
        self.location = location
        self.url = url
        self.notes = notes
        self.structuredPlace = structuredPlace
        self.geocodedPlace = geocodedPlace
    }
}

public enum CalendarKind: Sendable, Hashable { case regular, subscription, birthdays }
public enum Participation: Sendable, Hashable { case accepted, declined, tentative, unknown }

public struct Place: Sendable, Hashable {
    public let title: String
    public let address: String?
    public let latitude: Double
    public let longitude: Double

    public init(title: String, address: String? = nil, latitude: Double, longitude: Double) {
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasValidCoordinates: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public enum SuppressionRule: Sendable, Hashable {
    case series(calendarID: String, seriesID: String)
    case title(calendarID: String, title: String)

    func matches(_ event: CalendarEvent) -> Bool {
        switch self {
        case let .series(calendarID, seriesID):
            event.calendarID == calendarID && event.seriesID == seriesID
        case let .title(calendarID, title):
            event.calendarID == calendarID && event.title == title
        }
    }
}

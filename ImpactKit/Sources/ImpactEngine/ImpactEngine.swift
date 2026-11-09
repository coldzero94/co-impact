import Foundation

public struct ImpactEngine: Sendable {
    private let detector: NSDataDetector

    public init() throws {
        detector = try NSDataDetector(types:
            NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        )
    }

    /// The caller fetches the horizon and supplies any geocoding results; selection does no network I/O.
    public func card(
        for event: CalendarEvent, now: Date,
        suppressionRules: [SuppressionRule] = [], includedCalendarIDs: Set<String> = []
    ) -> ImpactCard? {
        guard Self.isUsersTimedEvent(event, includedCalendarIDs: includedCalendarIDs), event.end > now,
              !suppressionRules.contains(where: { $0.matches(event) }) else { return nil }

        let locationMatches = matches(in: event.location)
        let notesMatches = matches(in: event.notes)
        let noteLinks = webLinks(in: event.notes, matches: notesMatches)
        let links: [(URL, String)] = (event.url.map { [($0, "url")] } ?? [])
            + webLinks(in: event.location, matches: locationMatches).map { ($0, "location") }
            + noteLinks.map { ($0, "notes") }
        let meeting = links.first { Self.isMeetingURL($0.0) }
        let place: Place?
        let placeProvenance: Provenance
        if let structured = event.structuredPlace, structured.hasValidCoordinates {
            place = structured
            placeProvenance = .calendar(field: "structuredLocation")
        } else {
            place = canGeocode(event.location)
                ? event.geocodedPlace.flatMap { $0.hasValidCoordinates ? $0 : nil } : nil
            placeProvenance = .computed(by: "geocoding")
        }
        guard meeting != nil || place != nil else { return nil }
        // In-person cards leave 15 minutes after the start (PRODUCT.md → Card timeline); cards with a
        // meeting link (online and hybrid) leave at the end, which the first guard enforces.
        if meeting == nil, now >= event.start.addingTimeInterval(15 * 60) { return nil }

        var facts = [
            Fact(label: "Title", value: event.title, provenance: .calendar(field: "title")),
            Fact(label: "Start", value: event.start.ISO8601Format(), provenance: .calendar(field: "start")),
            Fact(label: "End", value: event.end.ISO8601Format(), provenance: .calendar(field: "end")),
        ]
        var actions: [ImpactAction] = []
        if let (url, field) = meeting {
            let provenance = Provenance.calendar(field: field)
            actions.append(ImpactAction(kind: .joinMeeting(url), provenance: provenance))
            facts.append(Fact(label: "Meeting", value: url.absoluteString, provenance: provenance))
        }
        if let place {
            actions.append(ImpactAction(kind: .directions(to: place), provenance: placeProvenance))
            facts.append(Fact(label: "Place", value: place.address ?? place.title, provenance: placeProvenance))
        }
        for url in noteLinks {
            if !Self.isMeetingURL(url) {
                let action = ImpactAction(kind: .openLink(url), provenance: .calendar(field: "notes"))
                if !actions.contains(action) { actions.append(action) }
            }
        }
        if meeting == nil, place != nil {
            // One Call per distinct `tel:` URL; none when `telURL` returns nil.
            var dialed: Set<URL> = []
            for (matches, field) in [(locationMatches, "location"), (notesMatches, "notes")] {
                for match in matches {
                    if let phone = match.phoneNumber, let url = Self.telURL(phone), dialed.insert(url).inserted {
                        actions.append(ImpactAction(kind: .call(phone), provenance: .calendar(field: field)))
                    }
                }
            }
        }
        return ImpactCard(
            id: event.id, title: event.title, start: event.start, end: event.end,
            kind: meeting == nil ? .inPerson : (place == nil ? .onlineMeeting : .hybrid),
            facts: facts, actions: actions
        )
    }

    /// True for the user's own valid timed event: not all-day, canceled, declined, or with an empty or
    /// inverted interval; organized or attended by the user when it has attendees; on a regular or
    /// opted-in calendar. Has no clock or suppression check; each caller adds the ones it needs.
    static func isUsersTimedEvent(_ event: CalendarEvent, includedCalendarIDs: Set<String>) -> Bool {
        !event.isAllDay && !event.isCanceled && event.participation != .declined && event.end > event.start
            && (!event.hasAttendees || event.isUserOrganizer || event.isUserAttendee)
            && (event.calendarKind == .regular || includedCalendarIDs.contains(event.calendarID))
    }

    /// Use before requesting a geocode; room labels and URL locations are not destinations.
    public func canGeocode(_ location: String?) -> Bool {
        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty, !location.contains("://"),
              matches(in: location).allSatisfy({ $0.url == nil }),
              location.range(of: #"회의실|\b(?:room|conf(?:erence)?)\b|\b(?:\d+f|f\s*\d+|\d+\s*(?:st|nd|rd|th)?\s*floor)\b|\d+\s*층"#,
                             options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        return true
    }

    private func matches(in text: String?) -> [NSTextCheckingResult] {
        guard let text else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private func webLinks(in text: String?, matches: [NSTextCheckingResult]) -> [URL] {
        guard let text else { return [] }
        return matches.compactMap { match in
            guard match.url != nil, let range = Range(match.range, in: text),
                  let url = URL(string: String(text[range])), Self.isWebURL(url) else { return nil }
            return url
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased()) && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool { meetingProvider(url) != nil }

    /// The `tel:` URL Call opens for a detected phone number: its ASCII digits, plus `+` when one comes before
    /// the first digit, as in "(+82) 2-555-0100"; nil when the number before any `;` or `,` has letters
    /// (e.g. 1-800-FLOWERS) or no digits, and then selection offers no Call.
    /// shortcut: the detector puts an extension or a pause after `;` or `,`, and only the number before it is
    /// dialed; pass the rest as a `,` pause once a device shows the Phone app accepts it (step 10).
    public static func telURL(_ number: String) -> URL? {
        let main = number.prefix { $0 != ";" && $0 != "," }
        let digits = main.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, !main.contains(where: \.isLetter) else { return nil }
        let plus = main.first { $0 == "+" || $0.isNumber } == "+" ? "+" : ""
        return URL(string: "tel:\(plus)\(digits)")
    }

    /// The provider's name for an allowlisted meeting link (PRODUCT.md → Signals), or nil for any other URL.
    public static func meetingProvider(_ url: URL) -> String? {
        guard isWebURL(url), let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return path.count >= 2 && ["j", "my", "w"].contains(path[0]) ? "Zoom" : nil
        }
        switch host {
        case "meet.google.com":
            let code = path.count == 1
                && path[0].range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil
            return code ? "Google Meet" : nil
        case "teams.microsoft.com":
            return path.count >= 3 && path[0] == "l" && path[1] == "meetup-join" ? "Teams" : nil
        case "teams.live.com":
            return path.count >= 2 && path[0] == "meet" ? "Teams" : nil
        case "facetime.apple.com":
            return path == ["join"] ? "FaceTime" : nil
        default:
            guard host.hasSuffix(".webex.com"), path.count >= 2 else { return nil }
            return ["meet", "join"].contains(path[0]) || (path.count == 2 && path[1] == "j.php") ? "Webex" : nil
        }
    }
}

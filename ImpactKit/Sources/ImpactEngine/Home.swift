import Foundation

/// What Home shows (UX.md → Home; PRODUCT.md → Card timeline and Horizon).
public struct HomeSnapshot: Sendable, Hashable {
    /// The user's own timed events today that have not ended (`isUsersTimedEvent`): the summary's "of N".
    public let eventsLeftToday: Int
    /// UX.md → Home: the earliest card not done in its Soon or Now phase; otherwise the card not done
    /// that started most recently and is still running (the user may be late); otherwise the next one.
    public let nextUp: ImpactCard?
    /// Today's other cards by start time: done cards until they expire, and running cards that Next up
    /// has moved past, so a row can start before Next up.
    public let laterToday: [ImpactCard]
    /// PRODUCT.md → Horizon.
    public let tomorrowMorning: [ImpactCard]
    /// UX.md → Empty state: when no listed card is left to do, the first card not done after them that starts
    /// before `horizon`'s end; otherwise nil.
    public let next: ImpactCard?
    /// The listed cards whose primary action has run; Home shows them subdued with a checkmark.
    public let doneCardIDs: Set<String>
    /// Impacts recorded today: the ring's filled segments.
    public let impactsToday: Int
    /// The Impact ring's segments: one per Impact today plus one per card still to do today.
    /// Expired cards drop out instead of counting as missed (P7).
    public let ringSegments: Int

    /// Every card Home lists, in screen order.
    public var cards: [ImpactCard] { [nextUp].compactMap(\.self) + laterToday + tomorrowMorning }
}

extension ImpactEngine {
    /// `events` is the fetch (`horizon`); occurrence IDs must be unique (debug builds assert it on the listed
    /// cards). `completedCardIDs` holds cards whose primary action ran on any day, so a card done the evening
    /// before stays done; among unlisted cards they only keep a done one from being `next`. `impactsToday`
    /// counts every Impact recorded today and must not be negative. `calendar` sets the day boundaries and the
    /// 18:00 and noon cut-offs.
    public func home(
        events: [CalendarEvent], now: Date, calendar: Calendar, completedCardIDs: Set<String>, impactsToday: Int,
        suppressionRules: [SuppressionRule] = [], includedCalendarIDs: Set<String> = []
    ) -> HomeSnapshot {
        precondition(impactsToday >= 0, "impactsToday \(impactsToday) < 0")
        let (tomorrow, tomorrowNoon, end) = Self.horizon(now: now, calendar: calendar)
        let select = { (event: CalendarEvent) in
            card(for: event, now: now, suppressionRules: suppressionRules, includedCalendarIDs: includedCalendarIDs)
        }
        // A card keeps its event's start and ID, so sorting events first gives the cards' order.
        let inOrder = { (events: [CalendarEvent]) in events.sorted { ($0.start, $0.id) < ($1.start, $1.id) } }
        let cards = { (events: [CalendarEvent]) in inOrder(events).compactMap(select) }

        let todaysEvents = events.filter { $0.start < tomorrow }
        let todayCards = cards(todaysEvents)
        let toDo = todayCards.filter { !completedCardIDs.contains($0.id) }
        let nextUp = toDo.first { Self.isSoonOrNow($0, now: now) } ?? toDo.last { $0.start <= now } ?? toDo.first
        let showTomorrow = calendar.component(.hour, from: now) >= 18 || todayCards.isEmpty
        let tomorrowCards = showTomorrow
            ? Array(cards(events.filter { $0.start >= tomorrow && $0.start < tomorrowNoon }).prefix(2)) : []
        let listed = todayCards + tomorrowCards
        let listedIDs = Set(listed.map(\.id))
        assert(listedIDs.count == listed.count, "Duplicate occurrence IDs in \(listed.map(\.id))")
        let notDone = { (card: ImpactCard) in !completedCardIDs.contains(card.id) }
        // A listed card still to do already leads. Otherwise every listed card is done, so the first card not
        // done from tomorrow on is unlisted; selection stops there instead of running on the whole week.
        let next = listed.contains(where: notDone) ? nil
            : inOrder(events.filter { $0.start >= tomorrow && $0.start < end }).lazy.compactMap(select)
                .first(where: notDone)

        return HomeSnapshot(
            eventsLeftToday: todaysEvents.count {
                $0.end > now && Self.isUsersTimedEvent($0, includedCalendarIDs: includedCalendarIDs)
            },
            nextUp: nextUp,
            laterToday: todayCards.filter { $0.id != nextUp?.id },
            tomorrowMorning: tomorrowCards,
            next: next,
            doneCardIDs: completedCardIDs.intersection(listedIDs),
            impactsToday: impactsToday,
            ringSegments: impactsToday + toDo.count
        )
    }

    /// The day boundaries of Home and its fetch: `tomorrow` is where today ends, and events starting before `noon`
    /// tomorrow can be listed (PRODUCT.md → Horizon). Callers fetch from the start of today to `end`, the end of
    /// the sixth day after today, for the empty state's next card: within those days a weekday names one day.
    public static func horizon(now: Date, calendar: Calendar) -> (tomorrow: Date, noon: Date, end: Date) {
        guard let tomorrow = calendar.dateInterval(of: .day, for: now)?.end,
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow),
              // Where a day starts at 01:00 (DST at midnight), the day count keeps that hour; end at the day's start.
              let end = calendar.date(byAdding: .day, value: 6, to: tomorrow).map(calendar.startOfDay) else {
            preconditionFailure("\(calendar.identifier)/\(calendar.timeZone.identifier) cannot compute the days after \(now)")
        }
        return (tomorrow, noon, end)
    }

    /// Soon or Now (PRODUCT.md → Card timeline).
    /// shortcut: in-person cards count from the event start until leave-by (routing/ETA) exists.
    static func isSoonOrNow(_ card: ImpactCard, now: Date) -> Bool {
        let sinceStart = now.timeIntervalSince(card.start)
        return card.kind == .inPerson
            ? (-30 * 60 ..< 0).contains(sinceStart)
            : (-15 * 60 ..< 10 * 60).contains(sinceStart)
    }
}

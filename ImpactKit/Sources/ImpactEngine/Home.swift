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
    /// The listed cards whose primary action has run; Home shows them subdued with a checkmark.
    public let doneCardIDs: Set<String>
    /// The Impact ring: one segment per Impact today plus one per card still to do today.
    /// Expired cards drop out instead of counting as missed (P7).
    public let ringSegments: Int
}

extension ImpactEngine {
    /// `events` is the fetched horizon (PRODUCT.md → Horizon). `completedCardIDs` holds cards whose
    /// primary action ran on any day, so a card done the evening before stays done; IDs outside the
    /// horizon are ignored. `impactsToday` counts every Impact recorded today. `calendar` sets the day
    /// boundaries and the 18:00 and noon cut-offs.
    public func home(
        events: [CalendarEvent], now: Date, calendar: Calendar, completedCardIDs: Set<String>, impactsToday: Int,
        suppressionRules: [SuppressionRule] = [], includedCalendarIDs: Set<String> = []
    ) -> HomeSnapshot {
        precondition(impactsToday >= 0, "impactsToday \(impactsToday) < 0")
        guard let tomorrow = calendar.dateInterval(of: .day, for: now)?.end,
              let tomorrowNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) else {
            preconditionFailure("\(calendar.identifier)/\(calendar.timeZone.identifier) cannot compute tomorrow or its noon from \(now)")
        }
        let cards = { (events: [CalendarEvent]) in
            let cards = events.compactMap {
                card(for: $0, now: now, suppressionRules: suppressionRules, includedCalendarIDs: includedCalendarIDs)
            }
            assert(Set(cards.map(\.id)).count == cards.count, "Duplicate occurrence IDs in \(cards.map(\.id))")
            return cards.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }

        let todaysEvents = events.filter { $0.start < tomorrow }
        let todayCards = cards(todaysEvents)
        let toDo = todayCards.filter { !completedCardIDs.contains($0.id) }
        let nextUp = toDo.first { Self.isSoonOrNow($0, now: now) } ?? toDo.last { $0.start <= now } ?? toDo.first
        let showTomorrow = calendar.component(.hour, from: now) >= 18 || todayCards.isEmpty
        let tomorrowCards = showTomorrow
            ? Array(cards(events.filter { $0.start >= tomorrow && $0.start < tomorrowNoon }).prefix(2)) : []

        return HomeSnapshot(
            eventsLeftToday: todaysEvents.count {
                $0.end > now && Self.isUsersTimedEvent($0, includedCalendarIDs: includedCalendarIDs)
            },
            nextUp: nextUp,
            laterToday: todayCards.filter { $0.id != nextUp?.id },
            tomorrowMorning: tomorrowCards,
            doneCardIDs: completedCardIDs.intersection((todayCards + tomorrowCards).map(\.id)),
            ringSegments: impactsToday + toDo.count
        )
    }

    /// Soon or Now (PRODUCT.md → Card timeline). Leave-by is not computed yet, so in-person cards
    /// count from the event start.
    static func isSoonOrNow(_ card: ImpactCard, now: Date) -> Bool {
        let sinceStart = now.timeIntervalSince(card.start)
        return card.kind == .inPerson
            ? (-30 * 60 ..< 0).contains(sinceStart)
            : (-15 * 60 ..< 10 * 60).contains(sinceStart)
    }
}

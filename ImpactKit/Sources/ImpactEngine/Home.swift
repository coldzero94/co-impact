import Foundation

/// What Home shows (UX.md → Home).
public struct HomeSnapshot: Sendable, Hashable {
    /// The user's own timed events today that have not ended: the summary line's "of N".
    public let eventsLeftToday: Int
    /// The earliest of today's cards that is not done.
    public let nextUp: ImpactCard?
    /// Today's other cards by start time; done cards stay until they expire.
    public let laterToday: [ImpactCard]
    /// At most two cards before noon tomorrow, from 18:00 or once nothing is left to do today.
    public let tomorrowMorning: [ImpactCard]
    /// The Impact ring: one segment per Impact today plus one per card still to do today.
    /// Expired cards drop out instead of counting as missed (P7).
    public let impactsToday: Int
    public let ringSegments: Int
}

extension ImpactEngine {
    /// `events` is the fetched horizon (PRODUCT.md → Horizon); `completedToday` holds the IDs of
    /// cards whose primary action ran today.
    public func home(
        events: [CalendarEvent], now: Date, calendar: Calendar, completedToday: Set<String>,
        suppressionRules: [SuppressionRule] = [], includedCalendarIDs: Set<String> = []
    ) -> HomeSnapshot {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let tomorrowNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) else {
            preconditionFailure("\(calendar.identifier) cannot compute tomorrow's noon")
        }
        let cards = { (events: [CalendarEvent]) in
            events.compactMap {
                card(for: $0, now: now, suppressionRules: suppressionRules, includedCalendarIDs: includedCalendarIDs)
            }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }

        let todaysEvents = events.filter { $0.start < tomorrow }
        let todayCards = cards(todaysEvents).filter { !Self.hasExpired($0, now: now) }
        let toDo = todayCards.filter { !completedToday.contains($0.id) }
        let nextUp = toDo.first
        let showTomorrow = calendar.component(.hour, from: now) >= 18 || toDo.isEmpty
        let tomorrowCards = showTomorrow
            ? cards(events.filter { $0.start >= tomorrow && $0.start < tomorrowNoon }).prefix(2) : []

        return HomeSnapshot(
            eventsLeftToday: todaysEvents.count {
                $0.end > now && Self.isUsersTimedEvent($0, includedCalendarIDs: includedCalendarIDs)
            },
            nextUp: nextUp,
            laterToday: todayCards.filter { $0.id != nextUp?.id },
            tomorrowMorning: Array(tomorrowCards),
            impactsToday: completedToday.count,
            ringSegments: completedToday.count + toDo.count
        )
    }

    /// In-person cards leave 15 minutes after the start (PRODUCT.md → Card timeline); the others
    /// leave at the event's end, which selection already enforces.
    static func hasExpired(_ card: ImpactCard, now: Date) -> Bool {
        card.kind == .inPerson && now >= card.start.addingTimeInterval(15 * 60)
    }
}

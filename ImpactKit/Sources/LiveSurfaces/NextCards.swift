import Foundation
import ImpactEngine

/// What the Lock Screen widget shows over time (`NextCardWidget`), apart from WidgetKit.
public enum NextCards {
    /// One moment of the widget: from `date` on, it shows `card` (Home's Next up, else the first card ahead,
    /// e.g. tomorrow's), or nothing; `soonOrNow` raises it in the Smart Stack.
    public struct Moment: Hashable, Sendable {
        public let date: Date
        public let card: ImpactCard?
        public let soonOrNow: Bool
    }

    /// Now, then each moment a card ahead changes phase (Soon, start, end of Now, expiry), at most 24, so the
    /// widget moves on from card to card while Impact does not run.
    public static func moments(events: [CalendarEvent], state: SurfaceState, now: Date, calendar: Calendar,
                               engine: ImpactEngine) -> [Moment] {
        // A card only ever leaves with time (it expires), so events without one now never get one: select once.
        let events = events.filter {
            engine.card(for: $0, now: now, suppressionRules: state.suppressionRules) != nil
        }
        let home = { (date: Date) in
            engine.home(events: events, now: date, calendar: calendar, completedCardIDs: state.completedCardIDs,
                        impactsToday: 0, suppressionRules: state.suppressionRules)
        }
        let first = home(now)
        let ahead = first.cards + first.liveActivityCards
        // In person: Soon (−30 min), start, expiry (+15 min). Online and hybrid: Soon (−15), start, end of Now (+10),
        // expiry (the end).
        let changes = Set(ahead.flatMap { card in
            card.kind == .inPerson
                ? [card.start - 30 * 60, card.start, card.start + 15 * 60]
                : [card.start - 15 * 60, card.start, card.start + 10 * 60, card.end]
        }).filter { $0 > now }
        return ([now] + changes.sorted().prefix(23)).map { date in
            let snapshot = date == now ? first : home(date)
            let card = snapshot.nextUp ?? snapshot.liveActivityCards.first
            return Moment(date: date, card: card, soonOrNow: card.map { ImpactEngine.isSoonOrNow($0, now: date) } ?? false)
        }
    }
}

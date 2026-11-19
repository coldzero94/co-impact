import CalendarSources
import Foundation
import ImpactEngine

/// What the widgets show over time (`NextCardWidget`) and what Impact's App Intents run, apart from WidgetKit and
/// App Intents.
public enum NextCards {
    /// What a widget or App Intent reads while Impact may not run: the days live Home fetches (entries past
    /// midnight treat tomorrow as today, so its afternoon is needed) and Impact's state. Nil when Impact cannot read
    /// the calendar.
    @MainActor public static func read(now: Date, calendar: Calendar)
        -> (events: [CalendarEvent], state: SurfaceState, engine: ImpactEngine)? {
        let (_, _, end) = ImpactEngine.horizon(now: now, calendar: calendar)
        guard EventKitCalendar.access == .granted,
              let events = EventKitCalendar().events(from: calendar.startOfDay(for: now), to: end),
              let engine = try? ImpactEngine() else { return nil }
        return (events, SurfaceStore()?.load() ?? SurfaceState(completed: [:], suppressionRules: []), engine)
    }

    /// Home at `now` as Impact shows it, from the calendar and Impact's state (its focus blocks marked as Home marks
    /// them); the ring counts that day's Impacts.
    public static func home(events: [CalendarEvent], state: SurfaceState, now: Date, calendar: Calendar,
                            engine: ImpactEngine) -> HomeSnapshot {
        engine.home(events: marked(events, focusBlocks: state.focusBlocks), now: now, calendar: calendar, completedCardIDs: state.completedCardIDs,
                    impactsToday: state.completed.values.count { calendar.isDate($0, inSameDayAs: now) },
                    suppressionRules: state.suppressionRules)
    }

    /// Whether a surface may run `card` now: one of today's, or one of tomorrow's already in its Now phase, when its
    /// Live Activity runs it (a meeting at 00:05 from 23:55; owner, 2026-11-17). Another day's card otherwise waits
    /// for its day, so a meeting is never joined the evening before.
    public static func runsNow(_ card: ImpactCard, now: Date, calendar: Calendar) -> Bool {
        card.start < ImpactEngine.horizon(now: now, calendar: calendar).tomorrow
            || ImpactEngine.nowPhase(of: card).contains(now)
    }

    /// What the widgets' button and the Next up control run: Home's Next up rule among the listed cards still to
    /// do that run now (`runsNow`). By day that is Home's Next up; just before midnight it can be a card of
    /// tomorrow in its Now phase, ahead of one ending that was joined elsewhere.
    public static func runnable(in home: HomeSnapshot, now: Date, calendar: Calendar,
                                where include: (ImpactCard) -> Bool = { _ in true }) -> ImpactCard? {
        // Home lists today's cards (and tomorrow morning's from 18:00) with Next up first: back in start order, as
        // the rule needs.
        ImpactEngine.nextUp(among: home.cards.filter { card in
            runsNow(card, now: now, calendar: calendar) && !home.doneCardIDs.contains(card.id) && include(card)
        }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }, now: now)
    }

    /// What "Join my next meeting" and "Directions to my next appointment" run: as `runnable`, among the cards
    /// with that action.
    public static func next(_ action: RunAction, in home: HomeSnapshot, now: Date, calendar: Calendar) -> ImpactCard? {
        runnable(in: home, now: now, calendar: calendar) { $0.confirmedActions.contains { action.matches($0.kind) } }
    }

    /// One moment of the widgets: from `date` on, they show `card` (the card that runs now, else the first card
    /// ahead, e.g. tomorrow's), or nothing; `soonOrNow` sets the entry's relevance (whether it
    /// changes anything is unverified: research/system-surfaces.md).
    public struct Moment: Hashable, Sendable {
        public let date: Date
        public let card: ImpactCard?
        public let soonOrNow: Bool
        /// Whether the widgets' button runs `card`, the card that runs now (`NextCards.runnable`), when it offers its
        /// action now (`ImpactCard.offers`) and no focus session runs on it; else `card` is another day's, which waits
        /// for its day, or shows without a button.
        public let runnable: Bool
        /// The next card still to do after `card`: the medium widget's Later column.
        public let later: ImpactCard?
        /// The Impact ring on the moment's day, as on Home: Impacts recorded that day, and its segments.
        public let impactsToday: Int
        public let ringSegments: Int
    }

    /// Now, then each moment a card ahead changes phase (Soon, start, end of Now, expiry) and midnight (the ring
    /// starts over), at most 24, so the widgets move on from card to card while Impact does not run.
    public static func moments(events: [CalendarEvent], state: SurfaceState, now: Date, calendar: Calendar,
                               engine: ImpactEngine) -> [Moment] {
        // A card only ever leaves with time (it expires), so events without one now never get one: select once.
        let events = marked(events, focusBlocks: state.focusBlocks).filter {
            engine.card(for: $0, now: now, suppressionRules: state.suppressionRules) != nil
        }
        let home = { (date: Date) in Self.home(events: events, state: state, now: date, calendar: calendar, engine: engine) }
        let first = home(now)
        let ahead = first.cards + first.liveActivityCards
        // In person: Soon (−30 min), start, expiry (15 minutes after the start, or the end if sooner). Online and
        // hybrid: Soon (−15), start, end of Now (+10), expiry (the end). A focus block: Soon (−15), start, and its end,
        // where Now and the block end together. A card of tomorrow also at the start of its Now phase, when it starts
        // to run (`runsNow`).
        let tomorrow = ImpactEngine.horizon(now: now, calendar: calendar).tomorrow
        let changes = Set(ahead.flatMap { card in
            let phases: [Date] = switch card.kind {
            case .inPerson: [card.start - 30 * 60, card.start, min(card.start + 15 * 60, card.end)]
            case .onlineMeeting, .hybrid: [card.start - 15 * 60, card.start, card.start + 10 * 60, card.end]
            case .focusBlock: [card.start - 15 * 60, card.start, card.end]
            }
            return phases + (card.start >= tomorrow ? [ImpactEngine.nowPhase(of: card).lowerBound] : [])
        } + [tomorrow]).filter { $0 > now }
        return ([now] + changes.sorted().prefix(23)).map { date in
            let snapshot = date == now ? first : home(date)
            let runnable = Self.runnable(in: snapshot, now: date, calendar: calendar)
            let card = runnable ?? snapshot.liveActivityCards.first
            let later = (snapshot.cards + snapshot.liveActivityCards)
                .filter { !state.completed.keys.contains($0.id) && $0.id != card?.id && $0.start >= (card?.start ?? date) }
                .min { ($0.start, $0.id) < ($1.start, $1.id) }
            // A focus block's button waits for its Soon phase, as on Home, and none shows during its session.
            let offered = runnable.map { card in
                card.primaryAction.map { card.offers($0, now: date) } ?? false && state.focus?.cardID != card.id
            } ?? false
            return Moment(date: date, card: card,
                          soonOrNow: card.map { ImpactEngine.isSoonOrNow($0, now: date) } ?? false,
                          runnable: offered,
                          later: later,
                          impactsToday: snapshot.impactsToday, ringSegments: snapshot.ringSegments)
        }
    }

    /// The events with their focus blocks marked (`CalendarEvent.focusGoal`): `focusBlocks` by event ID, with their
    /// goals' titles. Home and every surface mark them here, so all see the same cards.
    public static func marked(_ events: [CalendarEvent], focusBlocks: [String: String]) -> [CalendarEvent] {
        focusBlocks.isEmpty ? events : events.map { event in
            var event = event
            event.focusGoal = focusBlocks[event.id]
            return event
        }
    }

    /// When the widget reads the calendar again: after the last change ahead, and at least hourly, so an event
    /// added elsewhere shows within the hour while Impact does not run (about 24 reloads a day at most). `dates` are
    /// the moments' dates; the first is now, never a change to wait for.
    public static func reloadDate(after dates: [Date], now: Date) -> Date {
        let hour = now.addingTimeInterval(3_600)
        return min(dates.dropFirst().last ?? hour, hour)
    }
}

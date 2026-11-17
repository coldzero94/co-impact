#if os(iOS)
import ImpactEngine
import SwiftUI
import WidgetKit

/// The Next up widget (UX.md → System surfaces). On the Lock Screen: the next card's time, title, and key fact.
/// On the Home Screen: small adds the primary action, medium the next card after it; with no card, the Impact
/// ring. It reads the calendar itself and Impact's `SurfaceState`, so it moves on from card to card while Impact
/// does not run.
public struct NextCardWidget: Widget {
    public static let kind = "NextCard"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextCardProvider()) { entry in
            NextCardView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("The next event that needs you, and when.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}

/// What one moment of the widget shows: Home's Next up, else the first card ahead (tomorrow's), else nothing.
struct NextCardEntry: TimelineEntry {
    struct Shown: Hashable {
        let title: String
        let keyFact: String
        let symbol: String
        let start: Date
        let isToday: Bool
        /// The primary action's label and the link that runs it through Impact: nil without the run token, and
        /// unless the card runs now (`NextCards.Moment.runnable`).
        var actionLabel = ""
        var runURL: URL?
    }

    let date: Date
    let shown: Shown?
    var later: Shown?
    var impactsToday = 0
    var ringSegments = 0
    let canRead: Bool
    let relevance: TimelineEntryRelevance?
}

struct NextCardProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextCardEntry {
        NextCardEntry(date: .now, shown: .init(title: "Design review", keyFact: "Zoom", symbol: "video.fill",
                                               start: .now.addingTimeInterval(12 * 60), isToday: true),
                      canRead: true, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextCardEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { @MainActor in completion(Self.entries(now: .now)[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextCardEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = Self.entries(now: now)
            completion(Timeline(entries: entries, policy: .after(NextCards.reloadDate(after: entries.map(\.date), now: now))))
        }
    }

    /// The widget's moments (`NextCards.moments`) from the calendar and Impact's state; it reloads after the last
    /// one, or when Impact asks after a change. Without calendar access, one entry that says so.
    @MainActor static func entries(now: Date) -> [NextCardEntry] {
        let calendar = Calendar.autoupdatingCurrent
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else {
            return [NextCardEntry(date: now, shown: nil, canRead: false, relevance: nil)]
        }
        return NextCards.moments(events: events, state: state, now: now, calendar: calendar, engine: engine).map { moment in
            let show = { (card: ImpactCard) in
                NextCardEntry.Shown(title: card.title, keyFact: card.keyFact, symbol: card.symbol, start: card.start,
                                    isToday: calendar.isDate(card.start, inSameDayAs: moment.date),
                                    actionLabel: card.primaryAction?.kind.label ?? "",
                                    runURL: state.runToken.flatMap {
                                        moment.runnable && card.id == moment.card?.id
                                            ? LiveCard.runURL(cardID: card.id, token: $0) : nil
                                    })
            }
            let shown = moment.card.map(show)
            let relevance = moment.card.map {
                moment.soonOrNow
                    ? TimelineEntryRelevance(score: 1, duration: ImpactEngine.nowPhase(of: $0).upperBound.timeIntervalSince(moment.date))
                    : TimelineEntryRelevance(score: 0)
            }
            return NextCardEntry(date: moment.date, shown: shown, later: moment.later.map(show),
                                 impactsToday: moment.impactsToday, ringSegments: moment.ringSegments,
                                 canRead: true, relevance: relevance)
        }
    }
}

struct NextCardView: View {
    let entry: NextCardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                // Home Screen widgets wear Next up's accent with a card, the system background without one.
                if !isSystem {
                    Color.clear
                } else if entry.shown != nil {
                    LinearGradient(colors: [.indigo, .indigo.mix(with: .black, by: 0.3)], startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle().fill(.background)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spoken)
    }

    private var isSystem: Bool { family == .systemSmall || family == .systemMedium }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let shown = entry.shown {
                Label("\(time(shown)) · \(shown.title)", systemImage: shown.symbol)
            } else {
                Text(emptyLine)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let shown = entry.shown {
                    VStack(spacing: 1) {
                        // Another day's card names its day, so 8:00 tomorrow never reads as tonight.
                        if shown.isToday {
                            Image(systemName: shown.symbol).font(.caption).widgetAccentable()
                        } else {
                            Text(shown.start, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold))
                        }
                        Text(shown.start, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(size: 14, weight: .semibold)).minimumScaleFactor(0.6)
                    }
                } else {
                    Image(systemName: entry.canRead ? "checkmark" : "exclamationmark").font(.title3.weight(.semibold))
                }
            }
        case .systemSmall:
            if let shown = entry.shown { NextUp(shown: shown, time: time(shown)) } else { ring }
        case .systemMedium:
            if let shown = entry.shown {
                HStack(alignment: .top, spacing: 14) {
                    NextUp(shown: shown, time: time(shown))
                    if let later = entry.later {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Later").font(.caption.weight(.semibold)).opacity(0.75)
                            Text(time(later)).font(.headline).widgetAccentable()
                            Text(later.title).font(.subheadline).lineLimit(2)
                            Text(later.keyFact).font(.caption).opacity(0.75).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .foregroundStyle(.white)
            } else {
                HStack(spacing: 16) {
                    emptyMark.frame(width: 64, height: 64)
                    Text(emptyLine).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        default:
            if let shown = entry.shown {
                VStack(alignment: .leading, spacing: 1) {
                    Label(time(shown), systemImage: shown.symbol).font(.headline).widgetAccentable()
                    Text(shown.title).font(.body).lineLimit(1)
                    Text(shown.keyFact).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(emptyLine).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyLine: String { entry.canRead ? "Nothing needs you today." : "Impact can't read your calendar." }

    private var ring: some View {
        VStack(spacing: 8) {
            emptyMark.frame(width: 58, height: 58)
            Text(emptyLine).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
    }

    /// No card: the Impact ring, as on Home (UX.md → System surfaces); without the calendar, a warning instead of
    /// a count it could not make (hard rule 2).
    @ViewBuilder private var emptyMark: some View {
        if entry.canRead {
            ImpactRing(filled: entry.impactsToday, segments: entry.ringSegments).tint(.indigo)
        } else {
            Image(systemName: "calendar.badge.exclamationmark").resizable().scaledToFit().padding(8)
                .foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }

    /// "10:00 AM" today, "Tue 8:30 AM" for a card on another day.
    private func time(_ shown: NextCardEntry.Shown) -> String {
        shown.isToday ? shown.start.formatted(.dateTime.hour().minute())
            : shown.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var spoken: String {
        guard let shown = entry.shown else { return emptyLine }
        return "Next: \(shown.title) at \(time(shown)), \(shown.keyFact)"
    }
}

/// Next up on the Home Screen: key fact, time, title, and the primary action through Impact.
private struct NextUp: View {
    let shown: NextCardEntry.Shown
    let time: String
    /// Tinted and clear Home Screens draw widgets in one color: the button then keeps its text by being a faint pill.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(shown.keyFact, systemImage: shown.symbol).font(.caption.weight(.semibold)).lineLimit(1).opacity(0.85)
            Spacer(minLength: 0)
            Text(time).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6).widgetAccentable()
            // One line, so the 44-pt button (UX.md → Accessibility) fits under it.
            Text(shown.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let url = shown.runURL {
                Link(destination: url) {
                    Label(shown.actionLabel, systemImage: shown.symbol)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(renderingMode == .fullColor ? Color.indigo : .white)
                        .background(renderingMode == .fullColor ? Color.white : .white.opacity(0.25), in: .capsule)
                }
                .accessibilityLabel("\(shown.actionLabel), \(shown.title)")
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
#endif

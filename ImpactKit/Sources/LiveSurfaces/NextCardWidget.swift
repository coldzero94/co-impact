#if os(iOS)
import CalendarSources
import ImpactEngine
import SwiftUI
import WidgetKit

/// The Lock Screen widget (UX.md → System surfaces): the next card's time, title, and key fact. It reads the
/// calendar itself and Impact's `SurfaceState`, so it moves on from card to card while Impact does not run.
public struct NextCardWidget: Widget {
    public static let kind = "NextCard"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextCardProvider()) { entry in
            NextCardView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("The next event that needs you, and when.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
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
    }

    let date: Date
    let shown: Shown?
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
            // With nothing ahead there is no change to wait for: read the calendar again in an hour, not at once.
            completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .after(now.addingTimeInterval(3_600))))
        }
    }

    /// The widget's moments (`NextCards.moments`) from the calendar and Impact's state; it reloads after the last
    /// one, or when Impact asks after a change. Without calendar access, one entry that says so.
    @MainActor static func entries(now: Date) -> [NextCardEntry] {
        let calendar = Calendar.autoupdatingCurrent
        let (_, noon, _) = ImpactEngine.horizon(now: now, calendar: calendar)
        guard EventKitCalendar.access == .granted,
              let events = EventKitCalendar().events(from: calendar.startOfDay(for: now), to: noon),
              let engine = try? ImpactEngine() else {
            return [NextCardEntry(date: now, shown: nil, canRead: false, relevance: nil)]
        }
        let state = SurfaceStore()?.load() ?? SurfaceState(completedCardIDs: [], suppressionRules: [])
        return NextCards.moments(events: events, state: state, now: now, calendar: calendar, engine: engine).map { moment in
            let shown = moment.card.map {
                NextCardEntry.Shown(title: $0.title, keyFact: $0.keyFact, symbol: $0.symbol, start: $0.start,
                                    isToday: calendar.isDate($0.start, inSameDayAs: moment.date))
            }
            let relevance = moment.card.map {
                moment.soonOrNow
                    ? TimelineEntryRelevance(score: 1, duration: ImpactEngine.nowPhase(of: $0).upperBound.timeIntervalSince(moment.date))
                    : TimelineEntryRelevance(score: 0)
            }
            return NextCardEntry(date: moment.date, shown: shown, canRead: true, relevance: relevance)
        }
    }
}

struct NextCardView: View {
    let entry: NextCardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken)
    }

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
                        Image(systemName: shown.symbol).font(.caption).widgetAccentable()
                        Text(shown.start, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(size: 14, weight: .semibold)).minimumScaleFactor(0.6)
                    }
                } else {
                    Image(systemName: "checkmark").font(.title3.weight(.semibold))
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
#endif

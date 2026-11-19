import ImpactEngine
import LiveSurfaces
import SwiftUI

/// The daily review (UX.md → Daily review): today's Impacts and its one line, then earlier days, newest first. No
/// charts, no comparisons, no empty days. The first time it opens on an evening, today's tokens gather into the ring
/// (UX.md → The Impact moment).
struct DailyReviewView: View {
    let model: HomeModel
    /// The day the review opened on: its line stays that day's, even if the sheet stays open past midnight. State, so
    /// Home's refresh, which makes this view again each minute, does not move it.
    @State private var day: Date
    @State private var line: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The day (`DailyLog.key`) whose evening already saw the tokens gather.
    @AppStorage("reviewGathered") private var gathered = ""

    init(model: HomeModel) {
        self.model = model
        _day = State(initialValue: model.now)
        _line = State(initialValue: model.line(on: model.now))
    }

    var body: some View {
        let days = model.reviewDays
        let todayKey = DailyLog.key(for: day, calendar: model.calendar)
        let today = days.first { $0.key == todayKey }
        let entries = today?.entries ?? []
        NavigationStack {
            List {
                Section {
                    GatheringRing(symbols: entries.map(\.kind.symbol), segments: model.snapshot.ringSegments,
                                  gather: gathers(entries, today: todayKey)) { gathered = todayKey }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                Section("Today") {
                    ForEach(entries, id: \.self) { EntryRow(entry: $0) }
                    TextField("One line about today", text: $line)
                        .submitLabel(.done)
                        .onSubmit { model.setLine(line, on: day) }
                }
                ForEach(days.filter { $0.key != todayKey }, id: \.key) { day in
                    Section {
                        ForEach(day.entries, id: \.self) { EntryRow(entry: $0) }
                        if let line = day.line { Text(line).italic() }
                    } header: {
                        Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    }
                }
            }
            .navigationTitle("Today")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The line is kept however the sheet closes, and when Impact leaves the front, where iOS may end it unseen.
        .onDisappear { model.setLine(line, on: day) }
        .onChange(of: scenePhase) { if scenePhase != .active { model.setLine(line, on: day) } }
    }

    /// The tokens gather the first time the review opens from 18:00, on a day with Impacts.
    private func gathers(_ entries: [DailyLog.Entry], today: String) -> Bool {
        !entries.isEmpty && model.calendar.component(.hour, from: day) >= 18 && gathered != today
    }
}

/// "10:01 · Joined Design review", "16:30 · 50 min on Write a book": when, in the zone it was recorded in, then what.
private struct EntryRow: View {
    let entry: DailyLog.Entry
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = 72.0

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            // A string: `Text(_:format:)` would put the environment's time zone in place of the entry's.
            Text(entry.date.formatted(entry.timeFormat))
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: typeSize.isAccessibilitySize ? nil : timeWidth, alignment: .leading)
            Label(entry.text, systemImage: entry.kind.symbol).labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's Impact ring with its tokens. When `gather` is true as the review opens, the tokens travel up into the ring
/// one by one and fill it, then `gathered` runs; with Reduce Motion, the ring fills with a cross-fade instead.
private struct GatheringRing: View {
    let symbols: [String]
    let segments: Int
    let gathered: () -> Void
    /// Whether the tokens gather: decided once, as the review opens, and false again once they have, so an Impact
    /// added while the review is open just counts.
    @State private var gathering: Bool
    @State private var landed = 0
    @State private var success = 0
    /// The count's height, which the tokens rise past; it grows with Dynamic Type.
    @State private var labelHeight = 22.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 72.0

    /// shortcut: at most this many tokens travel; a busier day's ring still fills to its count.
    private static let shown = 7
    private let token = 30.0
    private let spacing = 8.0

    init(symbols: [String], segments: Int, gather: Bool, gathered: @escaping () -> Void) {
        self.symbols = symbols
        self.segments = segments
        self.gathered = gathered
        _gathering = State(initialValue: gather)
    }

    var body: some View {
        let tokens = Array(symbols.prefix(Self.shown))
        VStack(spacing: 14) {
            // Empty from the first frame when it gathers, so the filling is seen, with Reduce Motion too.
            ImpactRing(filled: gathering ? landed : symbols.count, segments: segments, lineWidth: 7)
                .frame(width: ringSize, height: ringSize)
                .accessibilityHidden(true) // the count below says it
            Text("\(symbols.count) \(symbols.count == 1 ? "Impact" : "Impacts") today")
                .font(.headline)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { labelHeight = $0 }
            if gathering, !reduceMotion {
                HStack(spacing: spacing) {
                    ForEach(tokens.indices, id: \.self) { index in
                        Token(symbol: tokens[index], inRing: index < landed,
                              offset: offset(index, of: tokens.count))
                            .frame(width: token, height: token)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.success, trigger: success)
        .task {
            guard gathering else { return }
            // After the sheet has risen, so the filling is not lost under it.
            try? await Task.sleep(for: .seconds(0.4))
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) { landed = symbols.count }
            } else {
                for index in tokens.indices {
                    withAnimation(.spring(duration: 0.45)) { landed = index + 1 }
                    try? await Task.sleep(for: .seconds(0.18))
                }
                withAnimation(.spring(duration: 0.4)) { landed = symbols.count }
            }
            // Closed before it finished: it plays the next time the review opens this evening.
            guard !Task.isCancelled else { return }
            success += 1
            gathered()
            gathering = false
        }
    }

    /// How far token `index` of `count` travels: to the ring's center, above the count.
    private func offset(_ index: Int, of count: Int) -> CGSize {
        let across: Double = (Double(count - 1) / 2 - Double(index)) * (token + spacing)
        let up: Double = ringSize / 2 + 2 * 14 + labelHeight + token / 2
        return CGSize(width: across, height: -up)
    }

    private struct Token: View {
        let symbol: String
        let inRing: Bool
        let offset: CGSize

        var body: some View {
            Circle().fill(Color.accentColor)
                .overlay { Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(.white) }
                .scaleEffect(inRing ? 0.3 : 1)
                .opacity(inRing ? 0 : 1)
                .offset(inRing ? offset : .zero)
        }
    }
}

extension DailyLog.Entry {
    /// Its clock time where it was recorded, the time the user saw, also after travel.
    var timeFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    /// "Joined Design review", "Left for Dentist", "50 min on Write a book" (UX.md → Daily review).
    var text: String {
        switch kind {
        case .joined: "Joined \(title)"
        case .left: "Left for \(title)"
        case .focused(let minutes): "\(minutes) min on \(title)"
        }
    }
}

extension DailyLog.Entry.Kind {
    var symbol: String {
        switch self {
        case .joined: "video.fill"
        case .left: "car.fill"
        case .focused: "timer"
        }
    }
}

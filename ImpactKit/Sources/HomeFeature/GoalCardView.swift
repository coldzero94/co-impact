import ImpactEngine
import SwiftUI

/// UX.md → Home: the goal-time card, below the time-bound cards. It names the goal and its free slot with Block time;
/// for 5 seconds after Block time it shows "Blocked" with Undo instead.
struct GoalCardView: View {
    let card: GoalTimeCard
    let now: Date
    let blocked: Bool
    let block: () -> Void
    let undo: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.goal.title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.primary.opacity(0.6))
            if blocked {
                HStack {
                    Label("Blocked", systemImage: "checkmark")
                        .font(.headline)
                    Spacer()
                    Button("Undo", action: undo)
                        .font(.headline)
                        .accessibilityLabel("Undo, remove the block for \(card.goal.title)")
                }
            } else {
                Text("\(Self.day(card.slot.start, now: now)) is free")
                    .font(.title3.weight(.semibold))
                Button(action: block) {
                    Label("Block time", systemImage: "calendar.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                // Bordered, not filled: Next up's action stays the one filled button on Home.
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.accentFill(colorScheme))
                .accessibilityLabel("Block \(Self.day(card.slot.start, now: now, spoken: true)) for \(card.goal.title)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Today 14:10", "Tomorrow 09:00", else "Thu 19:00" (spoken: "Thursday 19:00").
    static func day(_ start: Date, now: Date, spoken: Bool = false, calendar: Calendar = .autoupdatingCurrent) -> String {
        let time = start.formatted(.dateTime.hour().minute())
        if calendar.isDate(start, inSameDayAs: now) { return "\(spoken ? "today" : "Today") \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            return "\(spoken ? "tomorrow" : "Tomorrow") \(time)"
        }
        return start.formatted(.dateTime.weekday(spoken ? .wide : .abbreviated).hour().minute())
    }
}

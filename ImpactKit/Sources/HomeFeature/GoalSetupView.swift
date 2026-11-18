import ImpactEngine
import SwiftUI

/// UX.md → Goal setup: up to three goals, each a title, times per week, and Workday or Personal time, with the working
/// hours in one row below. Done keeps the goals with a title; it is enabled once one has one, or when goals were set
/// before, so the last one can be removed.
struct GoalSetupView: View {
    let model: HomeModel
    @State private var goals: [Goal]
    @State private var workingHours: WorkingHours
    @Environment(\.dismiss) private var dismiss

    init(model: HomeModel) {
        self.model = model
        _goals = State(initialValue: model.goals.goals.isEmpty ? [Self.newGoal()] : model.goals.goals)
        _workingHours = State(initialValue: model.goals.workingHours)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($goals) { $goal in
                        GoalRow(goal: $goal, number: (goals.firstIndex { $0.id == goal.id } ?? 0) + 1)
                    }
                    .onDelete { goals.remove(atOffsets: $0) }
                    if goals.count < 3 {
                        Button("Add a goal", systemImage: "plus") { goals.append(Self.newGoal()) }
                    }
                } footer: {
                    Text("Impact suggests free time for each goal on Home.")
                }
                Section {
                    NavigationLink {
                        WorkingHoursView(hours: $workingHours)
                    } label: {
                        LabeledContent("Working hours", value: workingHours.summary)
                    }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.setGoals(goals, workingHours: workingHours)
                        dismiss()
                    }
                    .disabled(model.goals.goals.isEmpty
                        && goals.allSatisfy { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }
    }

    private static func newGoal() -> Goal { Goal(id: UUID().uuidString, title: "") }
}

/// One goal: its title, times per week (1–5), and its window.
private struct GoalRow: View {
    @Binding var goal: Goal
    let number: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Goal \(number)", text: $goal.title, prompt: Text("Write a book"))
                .font(.headline)
            Stepper(value: $goal.timesPerWeek, in: 1...5) {
                Text(goal.timesPerWeek == 1 ? "Once a week" : "\(goal.timesPerWeek) times a week")
            }
            let window = Picker("When", selection: $goal.window) {
                Text("Workday").tag(Goal.Window.workday)
                Text("Personal time").tag(Goal.Window.personal)
            }
            // Segmented controls keep their text size; a menu grows with accessibility sizes.
            if typeSize.isAccessibilitySize {
                window.pickerStyle(.menu)
            } else {
                window.pickerStyle(.segmented).labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

/// The working days and hours. The end stays at least 15 minutes after the start, on the same day (PRODUCT.md →
/// Goal-time rules v1).
private struct WorkingHoursView: View {
    @Binding var hours: WorkingHours
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        Form {
            Section {
                ForEach(WorkingHours.weekdayOrder(calendar), id: \.self) { day in
                    Toggle(calendar.weekdaySymbols[day - 1], isOn: Binding {
                        hours.weekdays.contains(day)
                    } set: { on in
                        if on { hours.weekdays.insert(day) } else { hours.weekdays.remove(day) }
                    })
                }
            }
            Section {
                DatePicker("Start", selection: Binding {
                    WorkingHours.time(hours.start)
                } set: {
                    hours.start = WorkingHours.minutes($0)
                    if hours.end < hours.start + 15 { hours.end = min(hours.start + 60, WorkingHours.lastMinute) }
                }, in: WorkingHours.time(0)...WorkingHours.time(WorkingHours.lastMinute - 15), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: Binding {
                    WorkingHours.time(hours.end)
                } set: {
                    hours.end = WorkingHours.minutes($0)
                }, in: WorkingHours.time(min(hours.start + 15, WorkingHours.lastMinute))...WorkingHours.time(WorkingHours.lastMinute),
                displayedComponents: .hourAndMinute)
            }
        }
        .navigationTitle("Working hours")
    }
}

extension WorkingHours {
    static let lastMinute = 23 * 60 + 59

    /// "Mon–Fri, 09:00–18:00": a run of days as a range, other days listed.
    var summary: String {
        let calendar = Calendar.autoupdatingCurrent
        let order = Self.weekdayOrder(calendar)
        let names = calendar.shortWeekdaySymbols
        let chosen = order.indices.filter { weekdays.contains(order[$0]) }
        let dayText = if let first = chosen.first, let last = chosen.last, chosen.count >= 3, last - first == chosen.count - 1 {
            "\(names[order[first] - 1])–\(names[order[last] - 1])"
        } else {
            chosen.isEmpty ? "No days" : chosen.map { names[order[$0] - 1] }.joined(separator: ", ")
        }
        let time = { (minutes: Int) in Self.time(minutes).formatted(.dateTime.hour().minute()) }
        return "\(dayText), \(time(start))–\(time(end))"
    }

    /// `Calendar` weekday numbers in the order the user's week runs.
    static func weekdayOrder(_ calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// A time of day on a day around 1 January 2001, which has no daylight saving change, for pickers and formatting.
    static func time(_ minutes: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                             of: calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))) ?? .distantPast
    }

    static func minutes(_ time: Date) -> Int {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

#if DEBUG
#Preview("Goal setup") {
    GoalSetupView(model: try! HomeFixtures.sample())
}
#endif

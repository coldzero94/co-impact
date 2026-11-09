import ImpactEngine
import SwiftUI

/// Card detail (UX.md → Card detail): header, answer, the card's actions, and the place.
/// shortcut: no organizer, attendees, or notes excerpt until the card carries them (EventKit, step 7), and
/// no Suggested section until Foundation Models (step 8).
struct CardDetailView: View {
    let card: ImpactCard
    let model: HomeModel
    /// Runs the action; the closure gets the kind when the system could not open it.
    let run: (ImpactAction, @escaping (ActionKind) -> Void) -> Void
    @State private var failed: ActionKind?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title).font(.title.bold())
                        Text(times).font(.subheadline).foregroundStyle(.secondary)
                        Text(card.answer).font(.title3.weight(.semibold)).padding(.top, 6)
                    }
                    VStack(spacing: 10) {
                        ForEach(card.confirmedActions) { action in
                            actionButton(action, primary: action == card.primaryAction)
                        }
                    }
                    if let place = card.place {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(place.title, systemImage: "mappin").fontWeight(.medium)
                            if let address = place.address {
                                Text(address).font(.subheadline).foregroundStyle(.secondary).padding(.leading, 30)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .actionFailureAlert($failed)
    }

    /// "10:00 – 11:00 AM · in 12 min": the time chip (UX.md → Card anatomy) only while it adds to the range.
    private var times: String {
        let range = (card.start..<card.end).formatted(.interval.hour().minute())
        return switch Countdown(to: card.start, now: model.now) {
        case .now: "\(range) · Now"
        case .minutes(let minutes): "\(range) · in \(minutes) min"
        case .clock: range
        }
    }

    @ViewBuilder
    private func actionButton(_ action: ImpactAction, primary: Bool) -> some View {
        let done = model.log.isDone(action, on: card)
        let button = Button {
            run(action) { failed = $0 }
        } label: {
            Label(done ? action.kind.doneLabel : action.kind.label, systemImage: done ? "checkmark" : action.kind.symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel("\(done ? action.kind.doneLabel : action.kind.label), \(card.title)")
        // Done actions stay tappable (e.g. to rejoin) but drop to the subdued style.
        if primary && !done {
            button.buttonStyle(.borderedProminent).tint(.accentFill(colorScheme))
        } else {
            button.buttonStyle(.bordered).foregroundStyle(done ? .secondary : .primary)
        }
    }
}

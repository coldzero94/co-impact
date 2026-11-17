import ImpactEngine
import ImpactIntelligence
import LiveSurfaces
import SwiftUI

/// Card detail (UX.md → Card detail): header, answer, the card's actions, details, and, when the on-device model
/// finds any, up to two suggested next steps from the notes.
struct CardDetailView: View {
    let card: ImpactCard
    let model: HomeModel
    /// Runs the action; the closure gets the kind when the system could not open it.
    let run: (ImpactAction, @escaping (ActionKind) -> Void) -> Void
    @State private var failed: ActionKind?
    @State private var suggestions: [NextStep] = []
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
                    details
                    suggested
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
        // PRODUCT.md → Permissions: notifications are asked from the first card's detail, if not asked before.
        .task { await NowAlerts.askOnce() }
        .task(id: card.notes) {
            guard let notes = card.notes else { return }
            suggestions = await Suggestions.generate(title: card.title, notes: notes)
        }
        .actionFailureAlert($failed)
    }

    /// The place (from the calendar or geocoded), then the organizer, attendees, and the start of the notes as the
    /// calendar has them.
    /// shortcut: notes show as plain text; strip markup if synced notes carry HTML on a device (step 10).
    @ViewBuilder
    private var details: some View {
        let organizer = card.organizer
        let attendees = card.attendees
        let notes = card.notes
        if card.place != nil || organizer != nil || !attendees.isEmpty || notes != nil {
            VStack(alignment: .leading, spacing: 14) {
                if let place = card.place {
                    VStack(alignment: .leading, spacing: 2) {
                        detail(place.title, "mappin").fontWeight(.medium)
                        if let address = place.address {
                            Text(address).font(.subheadline).foregroundStyle(.secondary).padding(.leading, iconWidth + 8)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let organizer {
                    detail(organizer.isEmpty ? "Organized by an unnamed guest" : "Organized by \(organizer)", "person")
                }
                if !attendees.isEmpty {
                    detail(attendeeLine(attendees), "person.2").accessibilityLabel("Invited: " + attendeeLine(attendees))
                }
                if let notes {
                    detail(notes, "note.text").lineLimit(6).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("Notes: " + notes)
                }
            }
        }
    }

    /// Inferred, so in their own section with `sparkles` and "Suggested", never among facts or actions, each with
    /// the words of the notes it comes from (UX.md → Confirmed vs. inferred).
    @ViewBuilder
    private var suggested: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Suggested", systemImage: "sparkles").font(.headline)
                ForEach(suggestions, id: \.self) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.text)
                        Text("“\(step.quote)”").font(.footnote).italic().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Suggested: \(step.text). From the notes: \(step.quote)")
                }
            }
        }
    }

    @ScaledMetric private var iconWidth = 24.0

    /// A details line; icons of different widths share one column, so the texts line up. `text` stays a `String`:
    /// other people wrote it, and a `LocalizedStringKey` would turn Markdown links in it into taps.
    private func detail(_ text: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).frame(width: iconWidth).accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
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

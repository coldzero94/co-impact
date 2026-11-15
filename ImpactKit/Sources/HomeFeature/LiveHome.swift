import CalendarSources
import ImpactEngine
import os
import SwiftUI

/// The app outside debug fixtures (UX.md → Onboarding): asks for calendar access, then shows Home on the
/// user's calendar, refreshed every minute, when the calendar changes, and when the app comes to the front.
public struct LiveHome: View {
    @State private var access = EventKitCalendar.access
    @State private var calendarSource = EventKitCalendar()
    @State private var model: HomeModel?
    @State private var startFailure: String?
    @State private var requestFailed = false
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            switch access {
            case .granted:
                if let model {
                    HomeView(model: model)
                } else if let startFailure {
                    Text(startFailure).padding()
                } else {
                    ProgressView()
                }
            case .notDetermined:
                Onboarding(requestFailed: requestFailed) { await connect() }
            case .denied:
                AccessNeeded()
            }
        }
        .task(id: access) {
            guard access == .granted else { return }
            while !Task.isCancelled {
                refresh()
                // Wake at the next minute, when a countdown changes.
                let second = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(60 - second))
            }
        }
        .task {
            // Iterated on the main actor whichever thread posts it.
            for await _ in NotificationCenter.default.notifications(named: EventKitCalendar.changed).map({ _ in }) {
                refresh()
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            access = EventKitCalendar.access // the user may have changed it in Settings
            refresh()
        }
    }

    private func connect() async {
        do {
            access = try await calendarSource.requestAccess()
            requestFailed = false
        } catch {
            homeLog.error("Calendar access request failed: \(error)")
            requestFailed = true
            access = EventKitCalendar.access
        }
    }

    /// Fetches today through tomorrow noon (PRODUCT.md → Horizon) and rebuilds Home at the current time.
    private func refresh() {
        guard access == .granted else { return }
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let events = calendarSource.events(from: calendar.startOfDay(for: now),
                                           to: ImpactEngine.horizon(now: now, calendar: calendar).end)
        if let model {
            model.update(events: events, now: now)
            return
        }
        do {
            let file = try ImpactFile.standard()
            model = try HomeModel(events: events, now: now, calendar: calendar, log: ActionLog(impacts: file.load())) {
                do {
                    try file.save($0)
                } catch {
                    // The Impact still counts until the app quits; only its record across launches is lost.
                    homeLog.fault("Could not save Impacts: \(error)")
                }
            }
        } catch {
            startFailure = "Impact could not start: \(error.localizedDescription)"
        }
    }
}

/// UX.md → Onboarding: what Impact does in one sentence, and Connect Calendar.
struct Onboarding: View {
    let requestFailed: Bool
    let connect: () async -> Void
    @State private var asking = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MessageScreen {
            Text("Impact").font(.largeTitle.bold())
            Text("Impact finds the events in your calendar that need you, and gets you there in one tap.")
                .font(.title3)
        } action: {
            if requestFailed {
                Text("Calendar access could not be requested. Try again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                Task {
                    asking = true
                    await connect()
                    asking = false
                }
            } label: {
                Label("Connect Calendar", systemImage: "calendar")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.accentFill(colorScheme))
            .disabled(asking)
        }
    }
}

/// Without full access: why Impact needs it, and the way to Settings (UX.md → Onboarding).
struct AccessNeeded: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MessageScreen {
            Text("Impact needs your calendar").font(.title.bold())
            Text("It reads your events on this iPhone to find the ones that need you. In Settings, give Impact Full Access to Calendars.")
        } action: {
            #if os(iOS)
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    openURL(settings)
                } label: {
                    Text("Open Settings").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.accentFill(colorScheme))
            }
            #endif
        }
    }
}

/// A message centered on screen with its button pinned below; at large text sizes the message scrolls.
private struct MessageScreen<Message: View, Action: View>: View {
    @ViewBuilder let message: Message
    @ViewBuilder let action: Action

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { message }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .leading)
                    .padding(.horizontal, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) { action }.padding(24).background(.background)
        }
    }
}

#if DEBUG
#Preview("Onboarding") { Onboarding(requestFailed: false) {} }
#Preview("Access needed") { AccessNeeded() }
#endif

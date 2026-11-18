import CalendarSources
import ImpactEngine
import LiveSurfaces
import os
import SwiftUI
#if os(iOS)
import WidgetKit
#endif

/// The app outside debug fixtures (UX.md → Onboarding): asks for calendar access, then shows Home on the
/// user's calendar, refreshed on the built triggers in ARCHITECTURE.md → Refresh and platform constraints.
public struct LiveHome: View {
    @State private var access = EventKitCalendar.access
    @State private var calendarSource = EventKitCalendar()
    @State private var model: HomeModel?
    @State private var impactFile: ImpactFile?
    /// The stored Impacts could not be read at launch; each refresh tries again until they can.
    @State private var storedImpactsUnread = false
    /// Full access, but no calendar Impact reads (only subscriptions or Birthdays, or none).
    @State private var noCalendars = false
    @State private var startFailure: String?
    @State private var requestFailed = false
    /// A widget's or Live Activity's button, or an App Intent, asked Impact to run this card's action.
    @State private var runRequest: RunRequest?
    /// The secret Impact's own run links carry (`RunToken`).
    @State private var runToken = RunToken.load()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            switch access {
            case .granted:
                if noCalendars {
                    NoCalendars()
                } else if let model {
                    HomeView(model: model, runRequest: $runRequest)
                } else if let startFailure {
                    Text(startFailure).padding()
                } else {
                    ProgressView()
                }
            case .notDetermined:
                Onboarding(requestFailed: requestFailed) { await connect() }
            case .denied:
                AccessNeeded(restricted: false)
            case .restricted:
                AccessNeeded(restricted: true)
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
            // Runs on the view's main actor whichever thread posts; mapping to Void drops the non-Sendable
            // Notification.
            for await _ in NotificationCenter.default.notifications(named: EventKitCalendar.changed).map({ _ in }) {
                refresh()
            }
        }
        .onChange(of: scenePhase) {
            // A run request waits only while Impact is coming to the front, never for a later visit.
            if scenePhase == .background { runRequest = nil }
            guard scenePhase == .active else { return }
            access = EventKitCalendar.access // the user may have changed it in Settings
            refresh()
        }
        .onOpenURL { url in
            guard let id = LiveCard.cardID(fromRunURL: url, token: runToken) else {
                // Not from one of Impact's own surfaces (ARCHITECTURE.md → Privacy): Impact only opens.
                if LiveCard.isRunURL(url) { homeLog.notice("A run link without Impact's token was ignored") }
                return
            }
            run(RunRequest(cardID: id))
        }
        // Siri, Shortcuts, and the Next up control: an App Intent brought Impact to the front and left its request.
        .onChange(of: RunRequests.shared.pending, initial: true) {
            guard let request = RunRequests.shared.pending else { return }
            RunRequests.shared.pending = nil
            run(request)
        }
        // PRODUCT.md → Permissions: notifications are asked the first time a card reaches its Now phase while
        // Impact is open (Home refreshes each minute, so this sees it), if not asked before.
        .task(id: cardInNow) {
            if cardInNow { await NowAlerts.askOnce() }
        }
        #if os(iOS)
        // Scheduled Live Activities carry each card's one Now alert (PRODUCT.md → Interruptions). Unwanted ones end
        // as soon as the wanted cards change, in front or not; missing ones are requested each time Impact comes to
        // the front (so one that failed, e.g. while Live Activities were off, is tried again), never from the
        // background, where ActivityKit refuses them.
        .task(id: LiveSync(cards: wantedLiveCards, inFront: scenePhase == .active)) {
            guard let cards = wantedLiveCards else { return }
            await LiveActivities.sync(cards, request: scenePhase == .active)
        }
        // The Next up widget reads the calendar itself, and Impact's state from the App Group: write it and
        // reload the widget when either changes as Home sees it (Home's snapshot stands in for the calendar).
        .onChange(of: WidgetSync(state: model?.surfaceState(runToken: runToken), home: model?.snapshot, access: access,
                                 noCalendars: noCalendars),
                  initial: true) { _, sync in
            if let state = sync.state { SurfaceStore()?.save(state) }
            WidgetCenter.shared.reloadTimelines(ofKind: NextCardWidget.kind)
        }
        #endif
    }

    /// The Live Activities to keep: none once Impact cannot read the calendar (so none starts for an event it no
    /// longer sees), and nil (leave them be) until the first refresh has built Home.
    private var wantedLiveCards: [LiveCard]? {
        guard access == .granted, !noCalendars else { return [] }
        return model?.liveCards(runToken: runToken)
    }

    private func connect() async {
        do {
            access = try await calendarSource.requestAccess()
            // No prompt and no answer, e.g. the request was dropped: say so instead of doing nothing.
            requestFailed = access == .notDetermined
        } catch {
            homeLog.error("Calendar access request failed: \(error.logged, privacy: .public)")
            requestFailed = true
            access = EventKitCalendar.access
        }
    }

    private var cardInNow: Bool {
        scenePhase == .active && model?.snapshot.cards.contains { ImpactEngine.nowPhase(of: $0).contains(.now) } == true
    }

    /// A surface's button or an App Intent can resume Impact from hours ago: bring Home to the present first, so
    /// the action counts at the time it runs and finds the card as the calendar has it now.
    private func run(_ request: RunRequest) {
        refresh()
        guard model != nil, !noCalendars else {
            homeLog.notice("A run request arrived while Home cannot show; dropped")
            return
        }
        runRequest = request
    }

    /// Fetches today and the six days after it (`ImpactEngine.horizon`) and rebuilds Home at the current time.
    private func refresh() {
        guard access == .granted else { return }
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        guard let events = calendarSource.events(from: calendar.startOfDay(for: now),
                                                 to: ImpactEngine.horizon(now: now, calendar: calendar).end) else {
            access = EventKitCalendar.access
            noCalendars = access == .granted
            return
        }
        noCalendars = false
        if let model {
            model.update(events: events, now: now)
            if storedImpactsUnread, let stored = impactFile?.load() {
                storedImpactsUnread = false
                model.restore(stored)
            }
            return
        }
        // Storage never blocks Home: without a usable file, Impacts count until the app quits.
        let file: ImpactFile?
        do {
            file = try ImpactFile.standard()
        } catch {
            homeLog.fault("No place to store Impacts: \(error.logged, privacy: .public)")
            file = nil
        }
        let stored = file?.load()
        impactFile = file
        storedImpactsUnread = file != nil && stored == nil
        let dismissals = DefaultsStore<Dismissals>(.standard)
        let goals = DefaultsStore<GoalSettings>(.standard)
        let goalRecords = DefaultsStore<GoalRecords>(.standard)
        let source = calendarSource
        do {
            model = try HomeModel(events: events, now: now, calendar: calendar, log: ActionLog(impacts: stored ?? [:]),
                                  dismissals: dismissals.load() ?? Dismissals(), goals: goals.load() ?? GoalSettings(),
                                  goalRecords: goalRecords.load() ?? GoalRecords(),
                                  blocks: BlockWriter(add: { try source.addBlock(title: $0, during: $1) },
                                                      remove: { try source.removeBlock(eventID: $0) }),
                                  saveImpacts: file?.saver(stored: stored) ?? { impacts in
                                      homeLog.fault("\(impacts.count, privacy: .public) Impacts not saved: no place to store them")
                                  },
                                  saveDismissals: dismissals.save, saveGoals: goals.save,
                                  saveGoalRecords: goalRecords.save)
        } catch {
            homeLog.fault("Impact could not start: \(error.logged, privacy: .public)")
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
            Text("Impact").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("Impact finds the events in your calendar that need you, and gets you there in one tap.")
                .font(.title3)
        } action: {
            if requestFailed {
                Text("Calendar access could not be requested. Try again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                asking = true
                Task {
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

/// Without full access: why Impact needs it, and the way to Settings (UX.md → Onboarding). When access is
/// restricted the user cannot change it, so there is no Settings button (hard rule 8).
struct AccessNeeded: View {
    let restricted: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MessageScreen {
            Text("Impact needs your calendar").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(restricted
                 ? "It reads your events on this iPhone to find the ones that need you. Calendar access is restricted on this iPhone, so Impact can't read it."
                 : "It reads your events on this iPhone to find the ones that need you. In Settings, give Impact Full Access to Calendars.")
        } action: {
            #if os(iOS)
            if !restricted, let settings = URL(string: UIApplication.openSettingsURLString) {
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

/// Full access, but no calendar Impact reads, so it never claims an empty day it did not read (hard rule 2).
struct NoCalendars: View {
    var body: some View {
        MessageScreen {
            Text("No calendars to read").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("Impact reads the calendars of your accounts on this iPhone, such as iCloud, Google, or Exchange. Subscribed calendars and Birthdays are skipped.")
        } action: {
            EmptyView()
        }
    }
}

/// A message vertically centered, with its button pinned below; at large text sizes the message scrolls.
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
#Preview("Access needed") { AccessNeeded(restricted: false) }
#Preview("Access restricted") { AccessNeeded(restricted: true) }
#Preview("No calendars") { NoCalendars() }
#endif

/// When live Home syncs Live Activities: whenever the wanted cards change, and whenever Impact enters or leaves
/// the front.
private struct LiveSync: Equatable {
    let cards: [LiveCard]?
    let inFront: Bool
}

/// When live Home refreshes the Next up widget: when the done and dismissed cards, Home's snapshot, calendar
/// access, or whether any calendar is readable change.
private struct WidgetSync: Equatable {
    let state: SurfaceState?
    let home: HomeSnapshot?
    let access: CalendarAccess
    let noCalendars: Bool
}

#if os(iOS)
import BackgroundTasks
import ImpactEngine
import LiveSurfaces
import os
import WidgetKit

/// Background refresh (ARCHITECTURE.md → Refresh and platform constraints): when iOS lets Impact run in the
/// background, it reads the calendar and Impact's state as the widgets do, ends the Live Activities of cards that
/// changed or left, gives the cards that should have one but do not the fallback alert (ActivityKit refuses
/// requests from the background), and reloads the widgets.
@MainActor public enum BackgroundRefresh {
    /// Also listed in Info.plist → `BGTaskSchedulerPermittedIdentifiers`.
    public static let identifier = "io.github.coldzero94.impact.refresh"

    /// Asks iOS to run `run()` in 15 minutes at the earliest; it decides when, possibly never.
    public static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            homeLog.error("Background refresh not scheduled: \((error as NSError).code, privacy: .public)")
        }
    }

    public static func run() async {
        schedule()
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        // Without Impact's state (none written yet, or locked before the first unlock after a reboot) it does
        // nothing: syncing cards without the run token or the done cards would end every activity.
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar),
              let token = state.runToken else {
            homeLog.notice("Background refresh: the calendar or Impact's state cannot be read")
            return
        }
        let home = NextCards.home(events: events, state: state, now: now, calendar: calendar, engine: engine)
        let cards = home.liveActivityCards.compactMap { LiveCard($0, runToken: token) }
        // How often iOS lets it run on a device (ARCHITECTURE.md → To verify).
        homeLog.notice("Background refresh: \(cards.count, privacy: .public) cards want a Live Activity")
        await LiveActivities.sync(cards, request: false)
        WidgetCenter.shared.reloadTimelines(ofKind: NextCardWidget.kind)
    }
}
#endif

#if os(iOS)
import BackgroundTasks
import ImpactEngine
import LiveSurfaces
import os
import WidgetKit

/// Background refresh (ARCHITECTURE.md → Refresh and platform constraints): when iOS lets Impact run in the
/// background, it reads the calendar and Impact's state as the widgets do, ends the Live Activities of cards that
/// changed or left, gives the cards that should have one but do not, and whose Now phase is ahead, the fallback
/// alert (ActivityKit refuses requests from the background), and reloads the widgets. Its cards must equal live
/// Home's, or the sync ends their activities (`backgroundLiveCards` test): geocoded places (step 10) must reach this
/// path too.
/// shortcut: a run is not cancelled when Impact comes to the front, so one overlapping the front sync can add a
/// fallback alert the front sync just removed (two alerts for that card); make syncs wait for each other if a device
/// shows it.
@MainActor public enum BackgroundRefresh {
    /// Also listed in Info.plist → `BGTaskSchedulerPermittedIdentifiers`.
    public static let identifier = "io.github.coldzero94.impact.refresh"

    /// Asks iOS to run `run()` in 15 minutes at the earliest; it decides when, possibly never. The request goes out
    /// asynchronously: await the task to know it was made.
    @discardableResult public static func schedule() -> Task<Void, Never> {
        let identifier = identifier
        // Off the main thread, where iOS 27's `submitTaskRequest` must not run (`submit` may run anywhere).
        return Task.detached {
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
            do {
                if #available(iOS 27, *) {
                    // iOS 27 deprecates `submit`, which misses some errors.
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
            } catch {
                // `BGTaskSchedulerErrorDomain` 1 (unavailable) also means background refresh is off for Impact, or
                // the simulator (Platform facts).
                homeLog.error("Background refresh not scheduled: \(error.logged, privacy: .public)")
            }
        }
    }

    public static func run() async {
        let booking = schedule()
        await refresh()
        // Returning lets iOS suspend Impact: book the next run first.
        // shortcut: the wait ignores the run's expiry; stop waiting on cancellation if a device shows overruns.
        await booking.value
    }

    private static func refresh() async {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        // Without the calendar or Impact's state (none written yet, or locked before the first unlock after a reboot)
        // it does nothing: syncing cards without the run token or the done cards would end every activity.
        guard let (events, state, engine) = NextCards.read(now: now, calendar: calendar) else {
            homeLog.notice("Background refresh: the calendar cannot be read")
            return
        }
        guard let token = state.runToken else {
            homeLog.notice("Background refresh: Impact's state cannot be read")
            return
        }
        let home = NextCards.home(events: events, state: state, now: now, calendar: calendar, engine: engine)
        let cards = LiveCard.wanted(in: home, runToken: token, focus: state.focus)
        // How often iOS lets it run on a device (ARCHITECTURE.md → To verify).
        homeLog.notice("Background refresh: \(cards.count, privacy: .public) cards want a Live Activity")
        await LiveActivities.sync(cards, request: false)
        WidgetCenter.shared.reloadTimelines(ofKind: NextCardWidget.kind)
    }
}
#endif

import HomeFeature
import LiveSurfaces
import SwiftUI

@main
struct ImpactApp: App {
    #if DEBUG
    @State private var fixture = Self.fixtureHour.map { hour in Result { try HomeFixtures.sample(at: hour) } }
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // A tap on a fallback Now alert can launch Impact: its handler must be in place first.
        NowAlerts.handleTaps()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            switch fixture {
            case .success(let model)?:
                HomeView(model: model)
            case .failure(let error)?:
                Text("Impact could not start: \(error.localizedDescription)").padding()
            case nil:
                LiveHome()
            }
            #else
            LiveHome()
            #endif
        }
        // While Impact does not run, iOS may wake it to bring the surfaces up to date (`BackgroundRefresh`).
        .onChange(of: scenePhase) {
            if scenePhase == .background { BackgroundRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }

    #if DEBUG
    /// `-fixtureHour <hour>` shows the synthetic sample day frozen at that hour instead of the calendar.
    private static var fixtureHour: Double? {
        UserDefaults.standard.object(forKey: "fixtureHour") == nil ? nil : UserDefaults.standard.double(forKey: "fixtureHour")
    }
    #endif
}

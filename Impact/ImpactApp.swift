import HomeFeature
import ImpactEngine
import SwiftUI

@main
struct ImpactApp: App {
    var body: some Scene {
        WindowGroup {
            switch Result(catching: Self.home) {
            case .success(let home):
                HomeView(snapshot: home.snapshot, now: home.now)
            case .failure(let error):
                Text("Impact could not start: \(error.localizedDescription)").padding()
            }
        }
    }

    /// Debug builds show synthetic data (`-fixtureHour` sets its clock). Release builds never show
    /// demo data (UX.md → Onboarding), so they stay empty until EventKit arrives (roadmap step 7).
    private static func home() throws -> (snapshot: HomeSnapshot, now: Date) {
        #if DEBUG
        let hour = UserDefaults.standard.double(forKey: "fixtureHour")
        let fixture = try HomeFixtures.sample(at: hour > 0 ? hour : 9.8)
        return (fixture.snapshot, fixture.now)
        #else
        let now = Date.now
        let snapshot = try ImpactEngine().home(
            events: [], now: now, calendar: .current, completedCardIDs: [], impactsToday: 0)
        return (snapshot, now)
        #endif
    }
}

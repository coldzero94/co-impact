import HomeFeature
import ImpactEngine
import SwiftUI

@main
struct ImpactApp: App {
    var body: some Scene {
        WindowGroup {
            switch Result(catching: Self.home) {
            case .success(let home):
                HomeView(snapshot: home.snapshot, now: home.now, impactsToday: home.impactsToday)
            case .failure(let error):
                Text("Impact could not start: \(error.localizedDescription)").padding()
            }
        }
    }

    /// Debug builds show synthetic data. Release builds never show demo data (UX.md → Onboarding),
    /// so they stay empty until EventKit arrives (roadmap step 7).
    private static func home() throws -> (snapshot: HomeSnapshot, now: Date, impactsToday: Int) {
        #if DEBUG
        let fixture = try HomeFixtures.morning()
        return (fixture.snapshot, fixture.now, fixture.impactsToday)
        #else
        let now = Date.now
        let snapshot = try ImpactEngine().home(
            events: [], now: now, calendar: .current, completedCardIDs: [], impactsToday: 0)
        return (snapshot, now, 0)
        #endif
    }
}

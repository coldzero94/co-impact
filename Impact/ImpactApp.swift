import HomeFeature
import SwiftUI

@main
struct ImpactApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // shortcut: synthetic data with the clock read once at launch; EventKit and a ticking clock
            // arrive in roadmap step 7.
            switch Result(catching: { try HomeFixtures.sample(at: Self.fixtureHour) }) {
            case .success(let fixture):
                HomeView(snapshot: fixture.snapshot, now: fixture.now)
            case .failure(let error):
                Text("Impact could not start: \(error.localizedDescription)").padding()
            }
            #else
            // shortcut: release builds show only the name until EventKit (roadmap step 7); they never
            // claim an empty day they did not read (hard rule 2) and never show demo data.
            Text("Impact")
            #endif
        }
    }

    #if DEBUG
    /// `-fixtureHour <hour>` sets the sample day's clock; 0 or unset means 09:48.
    private static var fixtureHour: Double {
        let hour = UserDefaults.standard.double(forKey: "fixtureHour")
        return hour > 0 ? hour : 9.8
    }
    #endif
}

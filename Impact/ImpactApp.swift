import HomeFeature
import SwiftUI

@main
struct ImpactApp: App {
    #if DEBUG
    // shortcut: a sample day frozen at -fixtureHour; real events replace it in roadmap step 7.
    @State private var home = Result { try HomeFixtures.sample(at: Self.fixtureHour) }
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            switch home {
            case .success(let model):
                HomeView(model: model)
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

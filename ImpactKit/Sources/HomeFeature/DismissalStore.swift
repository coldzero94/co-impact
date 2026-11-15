import Foundation
import ImpactEngine
import os

/// Dismissals in `UserDefaults` (ARCHITECTURE.md → Storage): occurrence IDs, and the series IDs and titles the user
/// muted.
/// shortcut: standard defaults; they move to the App Group with the widgets (step 9).
struct DismissalStore {
    let defaults: UserDefaults
    static let key = "dismissals"

    /// The stored dismissals, pruned; none before the first one. Data that does not decode is kept under another
    /// key for diagnosis, and dismissing starts over.
    func load(now: Date) -> Dismissals {
        guard let data = defaults.data(forKey: Self.key) else { return Dismissals() }
        do {
            return try JSONDecoder().decode(Dismissals.self, from: data).pruned(now: now)
        } catch {
            homeLog.fault("Dismissals did not decode, kept aside: \(error.logged, privacy: .public)")
            defaults.set(data, forKey: "\(Self.key).unreadable")
            defaults.removeObject(forKey: Self.key)
            return Dismissals()
        }
    }

    func save(_ dismissals: Dismissals) {
        do {
            defaults.set(try JSONEncoder().encode(dismissals), forKey: Self.key)
        } catch {
            homeLog.fault("Could not encode dismissals: \(error.logged, privacy: .public)")
        }
    }
}

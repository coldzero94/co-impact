import Foundation
import ImpactEngine
import os

/// A value stored whole as JSON in `UserDefaults` (ARCHITECTURE.md → Storage): the dismissals, and the goals.
/// shortcut: standard defaults, loaded once in the foreground (widgets get the dismissals' rules through
/// `SurfaceState`); move a value to the App Group once background refresh or a widget needs it, and then never save
/// over data that could not be read.
struct DefaultsStore<Value: Codable> {
    let defaults: UserDefaults
    let key: String

    /// Private: the per-value initializers below fix the keys users' data is stored under.
    private init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    /// The stored value; nil before the first save. Data that does not decode is kept under another key for diagnosis,
    /// and the value starts over.
    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            homeLog.fault("Stored \(key, privacy: .public) did not decode, kept aside: \(error.logged, privacy: .public)")
            defaults.set(data, forKey: "\(key).unreadable")
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func save(_ value: Value) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            homeLog.fault("Could not encode \(key, privacy: .public): \(error.logged, privacy: .public)")
        }
    }
}

// The keys users' data is stored under: changing one loses it (`LiveDataTests` pins them).
extension DefaultsStore<Dismissals> {
    init(_ defaults: UserDefaults) { self.init(defaults: defaults, key: "dismissals") }
}

extension DefaultsStore<GoalSettings> {
    init(_ defaults: UserDefaults) { self.init(defaults: defaults, key: "goals") }
}

/// The user's goals and working hours (PRODUCT.md → Goals), and whether Home has offered goal setup (UX.md →
/// Onboarding). Stored as its synthesized `Codable` (and `Goal`'s and `WorkingHours`'): renaming a property, or
/// adding a non-optional one, sets stored goals aside; `LiveDataTests.goalStore` pins the format.
public struct GoalSettings: Sendable, Hashable, Codable {
    /// One to three, in setup order; empty before setup or after the user removed them all.
    public var goals: [Goal] = []
    public var workingHours = WorkingHours()
    /// Home's one-time "Set up to three goals" row was opened or swiped away, or goals were saved.
    public var offered = false

    public init(goals: [Goal] = [], workingHours: WorkingHours = WorkingHours(), offered: Bool = false) {
        self.goals = goals
        self.workingHours = workingHours
        self.offered = offered
    }
}

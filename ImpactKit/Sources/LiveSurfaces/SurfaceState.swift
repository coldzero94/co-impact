import Foundation
import ImpactEngine
import os

/// What the widgets need from Impact that the calendar does not hold (ARCHITECTURE.md → Storage): which cards are
/// done and when (for the ring's Impacts), which are dismissed or muted, and the run links' secret. Card IDs, times,
/// and muted titles only, like Impact's own storage; the widgets read events from the calendar themselves.
public struct SurfaceState: Codable, Hashable, Sendable {
    /// When each card's Impact was recorded, by card ID.
    public var completed: [String: Date]
    public var suppressionRules: [SuppressionRule]
    /// The secret Impact's run links carry (`RunToken`): widgets are Impact's own surfaces, and the App Group is
    /// Impact's alone. Nil until Impact writes it; widgets then show no action button.
    public var runToken: String?

    public init(completed: [String: Date], suppressionRules: [SuppressionRule], runToken: String? = nil) {
        self.completed = completed
        self.suppressionRules = suppressionRules
        self.runToken = runToken
    }

    public var completedCardIDs: Set<String> { Set(completed.keys) }
}

/// `SurfaceState` in the App Group's defaults: Impact writes it, its widgets read it.
public struct SurfaceStore {
    public static let appGroup = "group.io.github.coldzero94.impact"
    static let key = "surfaceState"
    let defaults: UserDefaults

    /// Nil when the App Group is not available (e.g. a build signed without its entitlement): `UserDefaults` would
    /// then quietly give the app and the widget separate, private defaults.
    public init?() {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil,
              let defaults = UserDefaults(suiteName: Self.appGroup) else {
            surfaceLog.notice("The App Group is not available: widgets cannot see what is done or dismissed")
            return nil
        }
        self.defaults = defaults
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The state Impact last wrote, or nil before the first write or when it does not decode (then the widgets
    /// show every card as not done until Impact writes again).
    public func load() -> SurfaceState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try JSONDecoder().decode(SurfaceState.self, from: data)
        } catch {
            surfaceLog.fault("Surface state did not decode: \((error as NSError).code, privacy: .public)")
            return nil
        }
    }

    public func save(_ state: SurfaceState) {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: Self.key)
        } catch {
            surfaceLog.fault("Could not encode the surface state: \((error as NSError).code, privacy: .public)")
        }
    }
}

let surfaceLog = Logger(subsystem: "io.github.coldzero94.impact", category: "surfaces")

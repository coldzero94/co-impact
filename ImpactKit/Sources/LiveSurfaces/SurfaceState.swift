import Foundation
import ImpactEngine
import os

/// What the widgets need from Impact that the calendar does not hold (ARCHITECTURE.md → Storage): which cards are
/// done and when (for the ring's Impacts), which are dismissed or muted, the run links' secret, which events are focus
/// blocks, and the running focus session. Of the calendar, card IDs, times, and muted titles only, plus the goals'
/// titles; the widgets read events themselves.
public struct SurfaceState: Codable, Hashable, Sendable {
    /// When each card's Impact was recorded, by card ID.
    public var completed: [String: Date]
    public var suppressionRules: [SuppressionRule]
    /// The secret Impact's run links carry (`RunToken`): widgets are Impact's own surfaces, and the App Group is
    /// Impact's alone. Nil only in the widgets' fallback when nothing decodes; they then show no action button.
    public var runToken: String?
    /// The focus blocks by event ID, with their goal's title (`CalendarEvent.focusGoal`), as Home marks them.
    public var focusBlocks: [String: String]
    /// The running focus session, so background refresh keeps its Live Activity.
    public var focus: FocusSession?

    public init(completed: [String: Date], suppressionRules: [SuppressionRule], runToken: String? = nil,
                focusBlocks: [String: String] = [:], focus: FocusSession? = nil) {
        self.completed = completed
        self.suppressionRules = suppressionRules
        self.runToken = runToken
        self.focusBlocks = focusBlocks
        self.focus = focus
    }

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
    /// show every card as not done, dismissed ones too, an empty ring, and no action button until Impact writes
    /// again).
    /// shortcut: a change of form (e.g. `completedCardIDs` to `completed`) drops the stored state until Impact
    /// next runs; decode the old form once Impact has users.
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

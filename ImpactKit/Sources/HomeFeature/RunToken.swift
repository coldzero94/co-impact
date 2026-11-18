import Foundation

/// The per-install secret in run links (ARCHITECTURE.md → Privacy): only Impact and its own surfaces know it, so
/// another app that can read card IDs still cannot run a card's action through `impact://run`. Kept in standard
/// `UserDefaults`, which other apps cannot read; the widgets get a copy in the App Group (`SurfaceState`), which
/// only Impact's targets can open.
enum RunToken {
    static let key = "runToken"

    /// The stored token, made on first use.
    /// shortcut: a read that fails (e.g. before the first unlock after a reboot) looks like a missing token and
    /// replaces it, so existing activities' buttons only open Impact until the next sync. Background refresh reads
    /// the App Group's copy instead (`BackgroundRefresh`); tell the two apart if a background launch ever loads it.
    static func load(_ defaults: UserDefaults = .standard) -> String {
        if let token = defaults.string(forKey: key), !token.isEmpty { return token }
        let token = UUID().uuidString
        defaults.set(token, forKey: key)
        return token
    }
}

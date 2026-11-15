import Foundation

/// The per-install secret in Live Activity run links (ARCHITECTURE.md → Privacy): only Impact and its own
/// activities know it, so another app that can read card IDs still cannot run a card's action through
/// `impact://run`. Kept in standard `UserDefaults`, which other apps cannot read.
enum RunToken {
    static let key = "runToken"

    /// The stored token, made on first use.
    static func load(_ defaults: UserDefaults = .standard) -> String {
        if let token = defaults.string(forKey: key), !token.isEmpty { return token }
        let token = UUID().uuidString
        defaults.set(token, forKey: key)
        return token
    }
}

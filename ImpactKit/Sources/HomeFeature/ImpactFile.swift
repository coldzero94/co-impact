import Foundation
import os

/// Recorded Impacts on disk (ARCHITECTURE.md → Storage): card IDs and times only, no calendar content.
/// shortcut: one JSON file in Application Support, rewritten whole on each Impact; it moves to the App Group
/// when widgets read it (step 9), and to a database if the daily log (step 13) needs one.
struct ImpactFile {
    let url: URL

    static func standard() throws -> ImpactFile {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return ImpactFile(url: folder.appending(path: "impacts.json"))
    }

    /// The stored Impacts, or none before the first one. A file that cannot be read is renamed with an
    /// `unreadable` suffix and kept for diagnosis, so the next save does not overwrite it.
    func load() -> [String: Date] {
        do {
            return try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        } catch {
            let aside = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            homeLog.fault("Impacts unreadable, set aside at \(aside.lastPathComponent, privacy: .public): \(error)")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
            } catch {
                homeLog.fault("Could not set aside unreadable Impacts: \(error)")
            }
            return [:]
        }
    }

    func save(_ impacts: [String: Date]) throws {
        try JSONEncoder().encode(impacts).write(to: url, options: .atomic)
    }
}

let homeLog = Logger(subsystem: "io.github.coldzero94.impact", category: "home")

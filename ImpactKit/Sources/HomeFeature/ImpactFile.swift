import Foundation
import os

/// Recorded Impacts on disk (ARCHITECTURE.md → Storage): card IDs (an item ID, plus the original start of a
/// recurring occurrence) and times; no titles, notes, places, or attendees.
/// shortcut: one JSON file in Application Support, rewritten whole on each Impact; it moves to the App Group
/// when widgets read it (step 9), and to a database if the daily log (step 13) needs one.
struct ImpactFile {
    let url: URL

    static func standard() throws -> ImpactFile {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return ImpactFile(url: folder.appending(path: "impacts.json"))
    }

    /// The stored Impacts, or none before the first one. Content that does not decode is renamed with an
    /// `unreadable` suffix and kept for diagnosis. nil means the file is there but could not be read now (it
    /// may be locked) or could not be set aside: then nothing may be saved over it.
    func load() -> [String: Date]? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        } catch {
            homeLog.fault("Impacts not readable now: \(error.logged, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            let aside = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            homeLog.fault("Impacts did not decode, setting aside as \(aside.lastPathComponent, privacy: .public): \(error.logged, privacy: .public)")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                return [:]
            } catch {
                homeLog.fault("Could not set aside undecodable Impacts: \(error.logged, privacy: .public)")
                return nil
            }
        }
    }

    func save(_ impacts: [String: Date]) throws {
        try JSONEncoder().encode(impacts).write(to: url, options: .atomic)
    }
}

let homeLog = Logger(subsystem: "io.github.coldzero94.impact", category: "home")

extension Error {
    /// The error's domain and code, which are safe to log publicly; the description may hold user data.
    var logged: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}

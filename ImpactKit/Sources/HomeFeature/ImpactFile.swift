import Foundation
import os

/// Recorded Impacts on disk (ARCHITECTURE.md → Storage): card IDs (an item ID, plus the original start of a
/// recurring occurrence) and times; no titles, notes, places, or attendees.
/// shortcut: one JSON file in Application Support, rewritten whole on each save (widgets get done cards through
/// `SurfaceState`); it moves to the App Group when background refresh reads it (step 10), and to a database if
/// the daily log (step 13) needs one.
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

    /// The save function for Home, given what `load()` returned. It never writes over Impacts it has not read:
    /// while they are unread it tries reading again on each save, merges once it can, and otherwise skips the
    /// save. Each save writes every Impact, so one that fails is stored by the next that succeeds.
    func saver(stored: [String: Date]?) -> ([String: Date]) -> Void {
        var known = stored
        return { impacts in
            if known == nil { known = load() }
            guard let earlier = known else {
                homeLog.fault("\(impacts.count, privacy: .public) Impacts not saved: the stored ones are still unreadable")
                return
            }
            do {
                // The earlier stamp wins, as in `ActionLog.restore`.
                try save(earlier.merging(impacts) { stored, new in min(stored, new) })
            } catch {
                homeLog.fault("Could not save Impacts: \(error.logged, privacy: .public)")
            }
        }
    }
}

let homeLog = Logger(subsystem: "io.github.coldzero94.impact", category: "home")

extension Error {
    /// The error's domain and code, and its underlying error's (e.g. the POSIX cause), which are safe to log
    /// publicly; descriptions may hold user data.
    var logged: String {
        let error = self as NSError
        let cause = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " (\($0.domain) \($0.code))" } ?? ""
        return "\(error.domain) \(error.code)\(cause)"
    }
}

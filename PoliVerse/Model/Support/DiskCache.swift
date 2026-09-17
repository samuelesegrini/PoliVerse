import Foundation
import OSLog

/// Small JSON cache in Application Support, so the app opens with content
/// instead of a spinner while the network round-trips.
///
/// Deliberately not the Keychain and deliberately not `UserDefaults`: this is
/// bulk, non-secret, disposable data. Anything sensitive (tokens) belongs in
/// ``KeychainStore``; anything tiny and scalar (a toggle) belongs in defaults.
nonisolated enum DiskCache {
    private static let log = Logger(subsystem: "one.wape.PoliVerse", category: "cache")

    private static var directory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let folder = base.appendingPathComponent("PoliVerseCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// A cached payload plus when it was written, so callers can decide whether
    /// it is too stale to show.
    struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
        let storedAt: Date

        func isFresh(within interval: TimeInterval) -> Bool {
            Date.now.timeIntervalSince(storedAt) < interval
        }
    }

    static func save<Value: Codable & Sendable>(_ value: Value, as name: String) {
        guard let url = directory?.appendingPathComponent("\(name).json") else { return }
        do {
            let entry = Entry(value: value, storedAt: .now)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Cache write \(name) failed: \(error.localizedDescription)")
        }
    }

    static func load<Value: Codable & Sendable>(_ type: Value.Type, as name: String) -> Entry<Value>? {
        guard
            let url = directory?.appendingPathComponent("\(name).json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Entry<Value>.self, from: data)
    }

    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        log.info("Cache cleared")
    }

    /// Total bytes on disk, for the Settings screen.
    static func sizeInBytes() -> Int {
        guard
            let directory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

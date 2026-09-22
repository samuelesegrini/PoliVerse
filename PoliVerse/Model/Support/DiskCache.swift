import Foundation
import OSLog

/// A small JSON cache in Application Support, so a screen opens with content
/// rather than a spinner.
///
/// For bulk, non-secret, disposable data. Credentials belong in ``KeychainStore``,
/// and small scalar preferences belong in `UserDefaults`. Per-account records that
/// must survive and be readable by the widgets belong in ``OfflineStore`` instead.
nonisolated enum DiskCache {
    /// Diagnostic log for this type, under the `cache` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "cache")

    /// `Application Support/PoliVerseCache`, created on first use. `nil` when
    /// Application Support cannot be located.
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

    /// A cached payload with the time it was written, so callers can decide whether it
    /// is too stale to show.
    struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        /// The cached payload.
        let value: Value
        /// When the payload was written.
        let storedAt: Date

        /// Whether the entry was written recently enough.
        ///
        /// - Parameter interval: How long an entry stays good, in seconds.
        /// - Returns: `true` when less than `interval` has passed since the write.
        func isFresh(within interval: TimeInterval) -> Bool {
            Date.now.timeIntervalSince(storedAt) < interval
        }
    }

    /// Encodes a value and writes it atomically as `<name>.json`.
    ///
    /// Failures are logged and otherwise ignored; a cache write is never load-bearing.
    ///
    /// - Parameters:
    ///   - value: The payload to cache.
    ///   - name: The file's base name.
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

    /// Reads a cached value.
    ///
    /// - Parameters:
    ///   - type: The shape to decode.
    ///   - name: The file's base name.
    /// - Returns: The entry with its write time, or `nil` when the file is absent or
    ///   will not decode.
    static func load<Value: Codable & Sendable>(_ type: Value.Type, as name: String) -> Entry<Value>? {
        guard
            let url = directory?.appendingPathComponent("\(name).json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Entry<Value>.self, from: data)
    }

    /// Removes the whole cache directory.
    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        log.info("Cache cleared")
    }

    /// Total size of the cached files, in bytes, as Impostazioni reports it. Zero when
    /// the directory cannot be read.
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

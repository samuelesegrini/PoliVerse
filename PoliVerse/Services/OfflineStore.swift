import Foundation
import OSLog

/// What the app keeps so it still works without signal.
///
/// ## Why this replaces the old cache
///
/// ``DiskCache`` stored two things — courses and rooms — under global names.
/// Everything else vanished when the network did, and `CareerService` went
/// further: a failed load actively wiped the gradebook, the sittings and the
/// libretto, so walking into a basement replaced a student's exam record with
/// an empty screen.
///
/// The names are also now **per account**. One person has a matricola per
/// enrolment, and a global key means the closed triennale's libretto shows
/// under the active magistrale. That is not a hypothetical: the career
/// switcher makes it a single tap away.
nonisolated final class OfflineStore: Sendable {
    private let directory: URL
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "offline")

    /// What came back, and how old it is.
    struct Entry<Value: Codable & Sendable>: Sendable {
        let value: Value
        /// Seconds since it was stored.
        let age: TimeInterval
    }

    static let shared = OfflineStore()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("PoliVerseOffline", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
    }

    private struct Stored<Value: Codable & Sendable>: Codable {
        let value: Value
        let storedAt: Date
    }

    /// Keyed by account, so two enrolments on one device cannot see each
    /// other's data.
    private func url(_ name: String, account: String) -> URL {
        let safe = account.replacingOccurrences(
            of: "[^A-Za-z0-9_-]", with: "", options: .regularExpression)
        return directory.appendingPathComponent("\(safe)-\(name).json")
    }

    /// - Parameter account: the matricola. **Nil is refused**: an anonymous
    ///   write is either sample data or a signed-out state, and neither
    ///   belongs on disk pretending to be somebody's record.
    func save<Value: Codable & Sendable>(_ value: Value, as name: String, account: String?) {
        guard let account, !account.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(Stored(value: value, storedAt: .now))
            try data.write(to: url(name, account: account), options: .atomic)
        } catch {
            log.error("offline write \(name, privacy: .public) failed: \(error.localizedDescription)")
        }
    }

    func load<Value: Codable & Sendable>(
        _ type: Value.Type, as name: String, account: String?
    ) -> Entry<Value>? {
        guard let account, !account.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: url(name, account: account)) else { return nil }
        // A shape change between releases must discard rather than crash or
        // half-decode.
        guard let stored = try? JSONDecoder().decode(Stored<Value>.self, from: data) else {
            log.info("offline \(name, privacy: .public) unreadable; discarded")
            return nil
        }
        return Entry(value: stored.value, age: Date.now.timeIntervalSince(stored.storedAt))
    }

    /// Testing seam: writes raw bytes so a corrupt file can be exercised.
    func write(_ data: Data, as name: String, account: String) {
        try? data.write(to: url(name, account: account), options: .atomic)
    }

    func clear(account: String) {
        let safe = account.replacingOccurrences(
            of: "[^A-Za-z0-9_-]", with: "", options: .regularExpression)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(safe)-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    var sizeInBytes: Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// How to describe what is on screen.
///
/// Showing cached data silently is the thing to avoid: a student looking at a
/// timetable has no way to tell yesterday's from today's, and the difference
/// is whether they turn up to a lecture that moved.
nonisolated struct Freshness: Sendable, Equatable {
    /// Seconds since the data was fetched, or nil if it never was.
    let age: TimeInterval?
    let isOnline: Bool

    /// Nil when there is nothing worth saying — online with recent data.
    var label: String? {
        if !isOnline {
            guard let age else { return "Offline" }
            return "Offline · \(Freshness.describe(age))"
        }
        guard let age, age > 900 else { return nil }
        return "Aggiornato \(Freshness.describe(age))"
    }

    /// True when the data is old enough that acting on it could mislead.
    var isStale: Bool {
        guard let age else { return true }
        return age > 3600 * 6
    }

    static func describe(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 60 { return "\(max(minutes, 1)) min fa" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ore fa" }
        return "\(hours / 24) giorni fa"
    }
}

/// One service's offline copy of one thing.
///
/// ## The mistake this prevents
///
/// The first version of offline support restored from disk in each service's
/// initialiser. Those run inside `PoliVerseApp.init()`; `Session.restore()`
/// runs later, from `RootView.task`. So at construction the matricola was
/// still nil, every restore asked for account `nil`, and nothing was ever
/// restored — a feature that looked finished and did nothing.
///
/// A slot restores **lazily**, keyed by the account it last restored for. It
/// therefore cannot run before the account is known, and runs again when the
/// account changes — which is one tap away now that careers can be switched.
nonisolated struct CachedSlot<Value: Codable & Sendable>: Sendable {
    let name: String
    private let store: OfflineStore
    /// The account the in-memory value belongs to, once there is one.
    private var restoredFor: String?
    /// Seconds since the value on screen was fetched, or nil if never.
    private(set) var age: TimeInterval?

    init(name: String, store: OfflineStore = .shared) {
        self.name = name
        self.store = store
    }

    /// The cached value, the first time it is asked for under a given account.
    ///
    /// Returns nil when there is nothing to restore *or* when this account has
    /// already been restored — a second restore would overwrite a fresher
    /// fetched value with what is on disk.
    mutating func restore(for account: String?) -> Value? {
        guard let account, !account.isEmpty, account != restoredFor else { return nil }
        restoredFor = account
        guard let entry = store.load(Value.self, as: name, account: account) else {
            return nil
        }
        age = entry.age
        return entry.value
    }

    mutating func save(_ value: Value, for account: String?) {
        guard let account, !account.isEmpty else { return }
        store.save(value, as: name, account: account)
        restoredFor = account
        age = 0
    }
}

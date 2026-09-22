import Foundation
import OSLog

/// The on-disk store that lets the app work without signal.
///
/// Each record is a JSON file named `<account>-<name>.json` in a directory inside
/// the app group, so the widget extension can read what the app wrote. Records are
/// keyed per account: one person has a matricola per enrolment, and a closed
/// triennale's libretto must not appear under the active magistrale.
///
/// ## Writing
///
/// ``save(_:as:account:)`` stamps the value with the current time and encodes and
/// writes it on a serial background queue, so no service encodes on the main
/// actor. Two saves of one record land in the order they were made. Everything
/// that reads or deletes waits for the queue first, so no caller observes a write
/// that has not landed, and no pending write restores a file that sign-out has
/// removed. The queue is per process rather than per store, because two stores can
/// name the same directory.
///
/// ## Reading
///
/// ``load(_:as:account:)`` returns the value with the age of the write. A record
/// that will not decode — because the shape changed between releases — is
/// discarded rather than trapped on.
///
/// An anonymous account is refused on both paths: it is either sample data or a
/// signed-out state, and neither belongs on disk as somebody's record.
nonisolated final class OfflineStore: Sendable {
    /// Where the record files live.
    private let directory: URL
    /// Diagnostic log for this type, under the `offline` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "offline")

    /// The serial queue every encode and write runs on, and that every read and delete
    /// waits behind. One per process, not one per store.
    private static let writes = DispatchQueue(label: "segrini.samuele.PoliVerse.offline-writes", qos: .utility)

    /// A record read back, with the age of the write that produced it.
    struct Entry<Value: Codable & Sendable>: Sendable {
        /// The decoded record.
        let value: Value
        /// Seconds since the record was written.
        let age: TimeInterval
    }

    /// The app group both the app and its extensions can reach.
    ///
    /// A widget runs in its own process, shares no Keychain and cannot sign in, so what
    /// the app writes has to land somewhere both can see.
    static let groupIdentifier = "group.segrini.samuele.PoliVerse"

    /// The store every service uses, backed by the app group.
    static let shared = OfflineStore(groupIdentifier: groupIdentifier)

    /// Creates a store over a directory, creating the directory if needed.
    ///
    /// - Parameters:
    ///   - directory: Where records live. Defaults to Application Support.
    ///   - legacy: A directory to copy existing records out of. See ``migrate(from:)``.
    init(directory: URL? = nil, migratingFrom legacy: URL? = nil) {
        self.directory = directory ?? Self.applicationSupportDirectory
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
        if let legacy { migrate(from: legacy) }
    }

    /// Creates a store in the app group's container, falling back to Application
    /// Support.
    ///
    /// The fallback covers a build without the entitlement or a profile that lacks the
    /// group: widgets are empty in that case, rather than the app losing every cached
    /// record. When the group is available, records already in Application Support are
    /// migrated into it.
    ///
    /// - Parameter groupIdentifier: The app group to look for.
    convenience init(groupIdentifier: String) {
        let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("PoliVerseOffline", isDirectory: true)
        self.init(directory: shared ?? Self.applicationSupportDirectory,
                  migratingFrom: shared == nil ? nil : Self.applicationSupportDirectory)
    }

    /// The per-app fallback directory inside Application Support.
    private static var applicationSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("PoliVerseOffline", isDirectory: true)
    }

    /// Copies JSON records written before the move into the app group.
    ///
    /// Copied rather than moved, so a downgrade still finds its data, and never over a
    /// file already present, since that file was written by this build and is the
    /// newer of the two.
    ///
    /// - Parameter legacy: The directory to copy from. Ignored when it is the store's
    ///   own directory.
    private func migrate(from legacy: URL) {
        flush()
        guard legacy != directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: legacy, includingPropertiesForKeys: nil)
        else { return }

        var moved = 0
        for file in files where file.pathExtension == "json" {
            let destination = directory.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            do {
                try FileManager.default.copyItem(at: file, to: destination)
                moved += 1
            } catch {
                log.error("offline migration of \(file.lastPathComponent, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
        if moved > 0 {
            log.notice("offline: migrated \(moved, privacy: .public) files into the shared container")
        }
    }

    /// The on-disk envelope: the record and when it was written.
    private struct Stored<Value: Codable & Sendable>: Codable, Sendable {
        /// The record as it was handed to ``OfflineStore/save(_:as:account:)``.
        let value: Value
        /// When the record was written, which ``Entry/age`` is measured from.
        let storedAt: Date
    }

    /// The file for one record of one account.
    ///
    /// - Parameters:
    ///   - name: The record name.
    ///   - account: The matricola, sanitised by ``safe(_:)``.
    /// - Returns: `<directory>/<account>-<name>.json`.
    private func url(_ name: String, account: String) -> URL {
        directory.appendingPathComponent("\(Self.safe(account))-\(name).json")
    }

    /// An account string reduced to characters safe in a file name.
    ///
    /// - Parameter account: The matricola.
    /// - Returns: The input with everything but `A–Z`, `a–z`, `0–9`, `_` and `-`
    ///   removed.
    static func safe(_ account: String) -> String {
        String(account.unicodeScalars.filter { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "_", "-": true
            default: false
            }
        }.map(Character.init))
    }

    /// Stores one record for one account.
    ///
    /// The timestamp is taken now rather than when the write reaches the disk, so the
    /// age reported later is the age of the fetch. Encoding and writing happen on the
    /// background queue; the call returns immediately.
    ///
    /// - Parameters:
    ///   - value: The record to store.
    ///   - name: The record name.
    ///   - account: The matricola. A `nil` or empty account is ignored and nothing is
    ///     written.
    func save<Value: Codable & Sendable>(_ value: Value, as name: String, account: String?) {
        guard let account, !account.isEmpty else { return }
        // Stamped now, not when the queue gets to it: the age shown later is
        // the age of the fetch.
        let stored = Stored(value: value, storedAt: .now)
        let url = url(name, account: account)
        let log = log
        Self.writes.async {
            do {
                let data = try JSONEncoder().encode(stored)
                try data.write(to: url, options: .atomic)
            } catch {
                log.error("offline write \(name, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Blocks until every save made so far is on disk.
    func flush() {
        Self.writes.sync {}
    }

    /// Suspends until every save made so far is on disk.
    ///
    /// For a background task about to report completion, which may suspend the process
    /// with writes still queued.
    func flushed() async {
        await withCheckedContinuation { continuation in
            Self.writes.async { continuation.resume() }
        }
    }

    /// Runs a closure once every save made so far is on disk.
    ///
    /// Used before asking a widget to reload, so it reads the file just written rather
    /// than the one before it.
    ///
    /// - Parameter body: Run on the store's background queue.
    func afterPendingWrites(_ body: @escaping @Sendable () -> Void) {
        Self.writes.async(execute: body)
    }

    /// Reads one record for one account.
    ///
    /// Waits for pending writes first, so a value just saved is the value read. A file
    /// that will not decode is discarded and logged.
    ///
    /// - Parameters:
    ///   - type: The shape to decode.
    ///   - name: The record name.
    ///   - account: The matricola. A `nil` or empty account returns `nil`.
    /// - Returns: The record with its age, or `nil` when there is no usable file.
    func load<Value: Codable & Sendable>(
        _ type: Value.Type, as name: String, account: String?
    ) -> Entry<Value>? {
        guard let account, !account.isEmpty else { return nil }
        flush()
        guard let data = try? Data(contentsOf: url(name, account: account)) else { return nil }
        // A shape change between releases must discard rather than crash or
        // half-decode.
        guard let stored = try? JSONDecoder().decode(Stored<Value>.self, from: data) else {
            log.info("offline \(name, privacy: .public) unreadable; discarded")
            return nil
        }
        return Entry(value: stored.value, age: Date.now.timeIntervalSince(stored.storedAt))
    }

    /// Writes raw bytes as a record, bypassing encoding.
    ///
    /// A testing seam, for exercising a corrupt or truncated file.
    ///
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - name: The record name.
    ///   - account: The matricola.
    func write(_ data: Data, as name: String, account: String) {
        flush()
        try? data.write(to: url(name, account: account), options: .atomic)
    }

    /// Removes every record belonging to one account.
    ///
    /// - Parameter account: The matricola.
    func clear(account: String) {
        flush()
        let safe = Self.safe(account)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(safe)-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Removes every record of every account and recreates the empty directory.
    func clearAll() {
        flush()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    /// Total size of every record on disk, in bytes. Zero when the directory cannot be
    /// read.
    var sizeInBytes: Int {
        flush()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// How to describe the age of what is on screen.
///
/// Turns an age and a reachability flag into one optional phrase, so cached data is
/// never shown silently: a student looking at a timetable cannot otherwise tell
/// yesterday's from today's.
nonisolated struct Freshness: Sendable, Equatable {
    /// Seconds since the data was fetched, or `nil` if it never was.
    let age: TimeInterval?
    /// Whether there is a usable connection.
    let isOnline: Bool

    /// The phrase to show, or `nil` when there is nothing worth saying.
    ///
    /// Offline always says so, with the age when there is one. Online says nothing
    /// until the data is more than fifteen minutes old.
    var label: String? {
        if !isOnline {
            guard let age else { return String(localized: "Offline") }
            return String(localized: "Offline · \(Freshness.describe(age))")
        }
        guard let age, age > 900 else { return nil }
        return String(localized: "Aggiornato \(Freshness.describe(age))")
    }

    /// Whether the data is old enough that acting on it could mislead: more than six
    /// hours old, or never fetched.
    var isStale: Bool {
        guard let age else { return true }
        return age > 3600 * 6
    }

    /// An age as a localised phrase — minutes, hours or days ago.
    ///
    /// - Parameter age: Seconds since the fetch.
    /// - Returns: The phrase. An age under a minute reports one minute rather than
    ///   zero.
    static func describe(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 60 { return String(localized: "\(max(minutes, 1)) min fa") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours) ore fa") }
        return String(localized: "\(hours / 24) giorni fa")
    }
}

/// One service's offline copy of one record, restored lazily and keyed by account.
///
/// Restoring lazily is what makes the copy usable: services are constructed in
/// ``PoliVerseApp/init()``, before ``LoginFlow/restore()`` has run, so at
/// construction there is no matricola to restore for. A slot restores the first
/// time it is asked under a given account, and again when the account changes —
/// which a career switch does in one tap.
///
/// ``Store`` does the same for sources; this serves the models that fetch by hand.
nonisolated struct CachedSlot<Value: Codable & Sendable>: Sendable {
    /// The record name in the offline store.
    let name: String
    /// Where the record is read from and written to.
    private let store: OfflineStore
    /// The account the in-memory value belongs to, once there is one.
    private var restoredFor: String?
    /// Seconds since the held value was fetched, or `nil` if it never was. Zero
    /// immediately after ``save(_:for:)``.
    private(set) var age: TimeInterval?

    /// Creates a slot for one record.
    ///
    /// - Parameters:
    ///   - name: The record name.
    ///   - store: Where the record lives.
    init(name: String, store: OfflineStore = .shared) {
        self.name = name
        self.store = store
    }

    /// The stored value, the first time it is asked for under a given account.
    ///
    /// - Parameter account: The matricola to restore for.
    /// - Returns: The stored value, or `nil` when there is nothing to restore, the
    ///   account is empty, or this account has already been restored — a second
    ///   restore would put disk contents back over a fresher fetch.
    mutating func restore(for account: String?) -> Value? {
        guard let account, !account.isEmpty, account != restoredFor else { return nil }
        restoredFor = account
        guard let entry = store.load(Value.self, as: name, account: account) else {
            return nil
        }
        age = entry.age
        return entry.value
    }

    /// Stores a value and marks this account as restored, so a later
    /// ``restore(for:)`` does not overwrite it.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - account: The matricola. A `nil` or empty account is ignored.
    mutating func save(_ value: Value, for account: String?) {
        guard let account, !account.isEmpty else { return }
        store.save(value, as: name, account: account)
        restoredFor = account
        age = 0
    }
}

/// The pointer an extension needs before it can read anything: which student's
/// records to open.
///
/// Offline records are keyed by matricola, and a widget has no session, so without
/// this it would face a container full of records and no way to tell which are the
/// reader's.
///
/// Holds a matricola and a display name in the app group's defaults. Nothing here
/// is a credential; tokens stay in the Keychain, which an extension cannot reach.
nonisolated struct SharedAccount: Sendable {
    /// Defaults key for ``matricola``.
    private static let matricolaKey = "sharedMatricola"
    /// Defaults key for ``firstName``.
    private static let nameKey = "sharedFirstName"

    /// The app group's defaults, which both the app and its extensions read and write.
    /// Falls back to `.standard` when the suite is unavailable.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: OfflineStore.groupIdentifier) ?? .standard
    }

    /// Whose records an extension should read, or `nil` when signed out — which a
    /// widget renders as an invitation to sign in rather than as an empty day.
    static var matricola: String? {
        get { defaults.string(forKey: matricolaKey) }
        set { defaults.set(newValue, forKey: matricolaKey) }
    }

    /// The student's first name, for a widget that greets them.
    static var firstName: String? {
        get { defaults.string(forKey: nameKey) }
        set { defaults.set(newValue, forKey: nameKey) }
    }

    /// Points the extensions at a student.
    ///
    /// Called whenever the signed-in student changes, including on sign-out and on a
    /// career switch, both of which change whose records a widget should show.
    ///
    /// - Parameters:
    ///   - matricola: The matricola to read records for, or `nil` for signed out.
    ///   - firstName: The student's first name.
    static func update(matricola: String?, firstName: String?) {
        self.matricola = matricola
        self.firstName = firstName
    }
}

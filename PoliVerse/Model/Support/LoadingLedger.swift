import Foundation
import OSLog

/// What a request is being made for, carried down to the transport.
///
/// The transport sees a host and a path; which kind of data the request serves, and
/// whether anyone asked for it, is known where the load starts. ``Loader`` sets this
/// around a fetch, and ``RequestGate`` reads it when the request leaves. A request
/// made outside a loader has no context and is recorded as ``unattributed``.
nonisolated enum LoadContext {
    /// One load's description.
    struct Value: Sendable {
        /// The kind of data, a ``Resource``'s `id`. Never a path: paths carry the
        /// matricola.
        var part: String
        /// `true` for a warm-up nobody is waiting for.
        var speculative: Bool
    }

    /// The load the current task is part of, if a loader started it.
    @TaskLocal static var current: Value?

    /// The part recorded for a request made outside any loader.
    static let unattributed = "altro"
}

/// One request, as the ledger keeps it: how long it took and how it ended.
///
/// Deliberately small. It holds no path, no query, no body, no token and no
/// matricola, so the ledger can be put in a diagnostics report as it is.
nonisolated struct LedgerRequest: Codable, Equatable, Sendable {
    /// How a request ended.
    enum Outcome: String, Codable, Sendable {
        /// The server answered.
        case ok
        /// The request failed for a reason other than time.
        case failed
        /// No answer within the request's timeout.
        case timedOut
        /// The caller went away. Counted in neither times nor failures.
        case cancelled
    }

    /// The kind of data the request served.
    var part: String
    /// The service asked, by its ``ServiceDirectory/Service`` name.
    var host: String
    /// When it left.
    var start: Date
    /// How long until it ended, in milliseconds.
    var milliseconds: Int
    /// How it ended.
    var outcome: Outcome
    /// Whether it was a warm-up.
    var speculative: Bool
}

/// One opening of a screen.
nonisolated struct LedgerScreen: Codable, Equatable, Sendable {
    /// The screen's name, as its view gave it.
    var screen: String
    /// When it appeared.
    var opened: Date
    /// Milliseconds until its first content, or `nil` if it was left before any.
    var firstContent: Int?
    /// Milliseconds until everything it shows was there, or `nil` if it was left before.
    var complete: Int?
}

/// Warm-ups of one kind of data: how many keys were fetched, how many were then shown.
nonisolated struct LedgerSpeculation: Codable, Equatable, Sendable {
    /// The kind of data.
    var part: String
    /// When this was noted.
    var at: Date
    /// Keys a warm-up fetched.
    var sent: Int
    /// Keys served to someone while still fresh.
    var used: Int
}

/// Everything the ledger holds.
nonisolated struct LedgerContents: Codable, Equatable, Sendable {
    var requests: [LedgerRequest] = []
    var screens: [LedgerScreen] = []
    var speculation: [LedgerSpeculation] = []

    /// Whether nothing was recorded.
    var isEmpty: Bool { requests.isEmpty && screens.isEmpty && speculation.isEmpty }

    /// Drops what is older than `days` and keeps the newest entries within the caps,
    /// which hold the file under a megabyte.
    mutating func trim(now: Date, days: Int = 14) {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        requests = Array(requests.filter { $0.start >= limit }.suffix(LoadingLedger.requestCap))
        screens = Array(screens.filter { $0.opened >= limit }.suffix(LoadingLedger.screenCap))
        speculation = Array(speculation.filter { $0.at >= limit }.suffix(LoadingLedger.screenCap))
    }
}

/// What the ledger says over a span of days: the numbers the performance
/// requirements are checked against.
nonisolated struct LedgerReport: Equatable, Sendable {
    /// One screen's openings.
    struct Screen: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        /// How many times it was opened.
        var openings: Int
        /// Median and 90th percentile of the time to first content, in milliseconds.
        var firstContent: Spread?
        /// The same for the time until everything was there.
        var complete: Spread?
        /// Whether there are enough openings for the numbers to mean something.
        var isEnough: Bool
    }

    /// One kind of data on one service.
    struct Part: Equatable, Sendable, Identifiable {
        var id: String { "\(part)|\(host)" }
        var part: String
        var host: String
        /// Requests that ended, cancelled ones left out.
        var count: Int
        /// Median and 90th percentile of the answered requests, in milliseconds.
        var duration: Spread?
        /// The share that failed or timed out, 0 to 1.
        var failureShare: Double
        /// How many timed out.
        var timeouts: Int
    }

    /// A median and a 90th percentile, in milliseconds.
    struct Spread: Equatable, Sendable {
        var median: Int
        var p90: Int
    }

    /// The fewest openings of a screen for its numbers to be shown as reliable.
    static let minimumSample = 20

    var days: Int
    var screens: [Screen]
    var parts: [Part]
    /// Keys fetched by warm-ups.
    var speculativeSent: Int
    /// Of those, the ones shown while fresh.
    var speculativeUsed: Int

    /// The share of warm-ups that were used, or `nil` when there were none.
    var speculativeUsedShare: Double? {
        speculativeSent > 0 ? Double(speculativeUsed) / Double(speculativeSent) : nil
    }

    /// Whether there is nothing to show.
    var isEmpty: Bool { screens.isEmpty && parts.isEmpty && speculativeSent == 0 }

    /// Computes the report.
    ///
    /// - Parameters:
    ///   - contents: What the ledger holds.
    ///   - now: The end of the span.
    ///   - days: How far back to look.
    init(_ contents: LedgerContents, now: Date, days: Int = 14) {
        var recent = contents
        recent.trim(now: now, days: days)
        self.days = days

        screens = Dictionary(grouping: recent.screens, by: \.screen)
            .map { name, openings in
                Screen(name: name, openings: openings.count,
                       firstContent: Self.spread(openings.compactMap(\.firstContent)),
                       complete: Self.spread(openings.compactMap(\.complete)),
                       isEnough: openings.count >= Self.minimumSample)
            }
            .sorted { $0.name < $1.name }

        parts = Dictionary(grouping: recent.requests.filter { $0.outcome != .cancelled }) { "\($0.part)|\($0.host)" }
            .compactMap { _, requests -> Part? in
                guard let first = requests.first else { return nil }
                let failed = requests.filter { $0.outcome != .ok }
                return Part(part: first.part, host: first.host, count: requests.count,
                            duration: Self.spread(requests.filter { $0.outcome == .ok }.map(\.milliseconds)),
                            failureShare: Double(failed.count) / Double(requests.count),
                            timeouts: failed.filter { $0.outcome == .timedOut }.count)
            }
            .sorted { ($0.part, $0.host) < ($1.part, $1.host) }

        speculativeSent = recent.speculation.reduce(0) { $0 + $1.sent }
        speculativeUsed = recent.speculation.reduce(0) { $0 + $1.used }
    }

    /// The median and the 90th percentile of some values, by nearest rank.
    ///
    /// - Parameter values: The values, in any order.
    /// - Returns: The spread, or `nil` for no values.
    static func spread(_ values: [Int]) -> Spread? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func rank(_ share: Double) -> Int {
            sorted[min(sorted.count - 1, max(0, Int((share * Double(sorted.count)).rounded(.up)) - 1))]
        }
        return Spread(median: rank(0.5), p90: rank(0.9))
    }
}

/// The on-device record of how long loading takes.
///
/// Requests are noted by ``RequestGate``, screen openings by the `screenLedger`
/// view modifier, warm-ups by ``Loader``. Nothing leaves the phone unless the
/// student shares a diagnostics report, and nothing recorded identifies them: see
/// ``LedgerRequest``.
///
/// Noting is fire-and-forget from any thread, so a request never waits on its own
/// bookkeeping. The file is rewritten after every ``flushEvery`` notes and when a
/// screen's opening ends.
actor LoadingLedger {
    /// The app's ledger. Kept in memory only while tests run, so a test never reads
    /// what another one wrote.
    nonisolated static let shared: LoadingLedger = {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return LoadingLedger(file: underTest ? nil : folder?.appendingPathComponent("loading-ledger.json"))
    }()

    /// The most requests kept.
    nonisolated static let requestCap = 4000
    /// The most screen openings, and the most warm-up notes, kept.
    nonisolated static let screenCap = 1000
    /// How many notes may be held before the file is rewritten.
    nonisolated static let flushEvery = 25

    private let file: URL?
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "ledger")
    private var contents = LedgerContents()
    private var didRead = false
    private var unsaved = 0

    /// Creates a ledger.
    ///
    /// - Parameters:
    ///   - file: Where it is kept, or `nil` to keep it in memory only.
    ///   - now: The clock, for tests.
    init(file: URL?, now: @escaping @Sendable () -> Date = { Date.now }) {
        self.file = file
        self.now = now
    }

    // MARK: - Noting, from anywhere

    /// Notes a request without waiting.
    nonisolated func note(_ request: LedgerRequest) {
        Task(priority: .utility) { await self.record(request) }
    }

    /// Notes a screen's opening without waiting.
    nonisolated func note(_ screen: LedgerScreen) {
        Task(priority: .utility) { await self.record(screen) }
    }

    /// Notes warm-ups without waiting.
    nonisolated func noteSpeculation(part: String, sent: Int = 0, used: Int = 0) {
        guard sent > 0 || used > 0 else { return }
        Task(priority: .utility) { await self.recordSpeculation(part: part, sent: sent, used: used) }
    }

    // MARK: - Recording

    /// Records a request.
    func record(_ request: LedgerRequest) {
        readIfNeeded()
        contents.requests.append(request)
        didChange()
    }

    /// Records a screen's opening and saves, since these are few.
    func record(_ screen: LedgerScreen) {
        readIfNeeded()
        contents.screens.append(screen)
        flush()
    }

    /// Records warm-ups.
    func recordSpeculation(part: String, sent: Int, used: Int) {
        readIfNeeded()
        contents.speculation.append(.init(part: part, at: now(), sent: sent, used: used))
        didChange()
    }

    // MARK: - Reading

    /// The report over the last `days` days.
    func report(days: Int = 14) -> LedgerReport {
        readIfNeeded()
        return LedgerReport(contents, now: now(), days: days)
    }

    /// What is held, for tests.
    func snapshot() -> LedgerContents {
        readIfNeeded()
        return contents
    }

    /// Writes what is held, trimmed, to the file.
    func flush() {
        readIfNeeded()
        contents.trim(now: now())
        unsaved = 0
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: file, options: .atomic)
        } catch {
            log.error("Ledger not saved: \(error.localizedDescription)")
        }
    }

    /// Forgets everything and removes the file, for sign-out.
    func erase() {
        contents = LedgerContents()
        didRead = true
        unsaved = 0
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    private func didChange() {
        unsaved += 1
        if unsaved >= Self.flushEvery { flush() }
    }

    private func readIfNeeded() {
        guard !didRead else { return }
        didRead = true
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(LedgerContents.self, from: data) else { return }
        contents = saved
    }
}

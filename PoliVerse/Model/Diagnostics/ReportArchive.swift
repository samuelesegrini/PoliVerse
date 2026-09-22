import Foundation
import MetricKit
import OSLog

/// Keeps what MetricKit delivers, on the device, for as long as it is useful.
///
/// MetricKit hands each report over once, so each becomes a file here: one file per
/// report, written once and never updated, so a single atomic write is the whole cost.
/// ``maxFiles`` and ``maxBytes`` keep a phone that hangs every day from filling up with
/// evidence of it, oldest first.
///
/// Stored in Application Support rather than the app group: the widgets have no use for
/// these, and ``OfflineStore`` holds the student's data and is wiped on sign-out.
/// Diagnostics are neither, and must not be lost with it.
///
/// Nothing here is sent anywhere. See `docs/metrickit-performance.md` §1.10.
actor ReportArchive {
    /// Which of MetricKit's two streams a report came from.
    nonisolated enum Kind: String, Sendable {
        /// `metric` for the daily metrics payload, `diagnostic` for a crash, hang, CPU, disk
        /// write, launch or memory report.
        case metric, diagnostic
    }

    /// One stored report, as the viewer lists it.
    nonisolated struct Entry: Sendable, Identifiable, Hashable {
        /// Where the file is.
        let url: URL
        /// Which stream it came from, read back from the file's name.
        let kind: Kind
        /// The file's size.
        let bytes: Int
        /// When the file was written.
        let date: Date
        /// ``url``.
        var id: URL { url }
    }

    /// What the archive holds, as the diagnostics page reports it.
    nonisolated struct Summary: Sendable, Equatable {
        /// How many metric reports are stored.
        let metricCount: Int
        /// How many diagnostic reports are stored.
        let diagnosticCount: Int
        /// How much space they take together.
        let bytes: Int
        /// When the most recent arrived, or `nil` when the archive is empty.
        let latest: Date?
    }

    /// The archive the app writes to.
    static let shared = ReportArchive()

    /// Where the report files live.
    private let directory: URL
    /// How many reports to keep.
    private let maxFiles: Int
    /// How much space the reports may take together.
    private let maxBytes: Int
    /// Diagnostic log for this type, under the `metrics` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "metrics")

    /// Creates an archive. The directory is made on first write.
    ///
    /// - Parameters:
    ///   - directory: Where reports are stored. Defaults to `MetricKit` inside Application
    ///     Support.
    ///   - maxFiles: How many reports to keep.
    ///   - maxBytes: How much space they may take together.
    init(directory: URL? = nil, maxFiles: Int = 60, maxBytes: Int = 5_000_000) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("MetricKit", isDirectory: true)
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
    }

    /// Stores a report already encoded as JSON, then prunes.
    ///
    /// A failure is logged and otherwise ignored: losing a diagnostic is not worth
    /// surfacing.
    ///
    /// - Parameters:
    ///   - json: The encoded report.
    ///   - kind: Which stream it came from.
    ///   - label: What is inside — `crash`, `hang` — which ends up in the file name so that a
    ///     directory listing reads as a log.
    ///   - receivedAt: When it arrived, which names the file.
    func store(json: Data, kind: Kind, label: String? = nil, receivedAt: Date = .now) {
        do {
            try ensureDirectory()
            let url = directory.appendingPathComponent(fileName(kind: kind, label: label, at: receivedAt))
            try json.write(to: url, options: .atomic)
            log.notice("Stored \(kind.rawValue, privacy: .public) report \(label ?? "-", privacy: .public), \(json.count, privacy: .public) bytes")
        } catch {
            log.error("Could not store \(kind.rawValue, privacy: .public) report: \(error.localizedDescription, privacy: .public)")
        }
        prune()
    }

    /// Encodes and stores a metrics report, split by state-reporting domain.
    ///
    /// Encoded here rather than where it arrives: a day's report is real work, and nothing
    /// on screen is waiting for it.
    ///
    /// - Parameter report: What MetricKit delivered.
    func store(_ report: MetricReport) {
        let encoder = JSONEncoder()
        encoder.userInfo[MetricReport.encodingFormatKey] = MetricReport.EncodingFormat.byStateReportingDomain
        encoder.dateEncodingStrategy = .iso8601
        do {
            store(json: try encoder.encode(report), kind: .metric)
        } catch {
            log.error("Could not encode metric report: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Encodes and stores a diagnostic report, labelled by what it is about.
    ///
    /// - Parameter report: What MetricKit delivered.
    func store(_ report: DiagnosticReport) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            store(json: try encoder.encode(report), kind: .diagnostic, label: Self.label(for: report.result))
        } catch {
            log.error("Could not encode diagnostic report: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The short label for a diagnostic report's subject, which names its file.
    ///
    /// - Parameter result: What the report is about.
    /// - Returns: `crash`, `hang`, `cpu`, `diskwrite`, `launch`, `memory` or `other`.
    nonisolated static func label(for result: DiagnosticResult) -> String {
        switch result {
        case .crash: "crash"
        case .hang: "hang"
        case .cpuException: "cpu"
        case .diskWriteException: "diskwrite"
        case .appLaunch: "launch"
        case .memoryException: "memory"
        @unknown default: "other"
        }
    }

    /// Every stored report.
    ///
    /// Sorted by file name, which sorts by time because of how ``fileName(kind:label:at:)``
    /// is built.
    ///
    /// - Returns: The reports, newest first.
    func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let kind: Kind = url.lastPathComponent.contains("-diagnostic") ? .diagnostic : .metric
                return Entry(url: url, kind: kind, bytes: values?.fileSize ?? 0,
                             date: values?.contentModificationDate ?? .distantPast)
            }
    }

    /// What the archive holds.
    ///
    /// - Returns: The counts, the total size and the most recent arrival.
    func summary() -> Summary {
        let all = entries()
        return Summary(
            metricCount: all.count { $0.kind == .metric },
            diagnosticCount: all.count { $0.kind == .diagnostic },
            bytes: all.reduce(0) { $0 + $1.bytes },
            latest: all.first?.date)
    }

    /// Deletes every stored report.
    func removeAll() {
        for entry in entries() {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// Removes the oldest reports until both ``maxFiles`` and ``maxBytes`` hold.
    func prune() {
        var all = entries()
        var total = all.reduce(0) { $0 + $1.bytes }
        while let oldest = all.last, all.count > maxFiles || total > maxBytes {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
            all.removeLast()
        }
    }

    /// Creates the archive directory if it is missing, excluded from backup.
    ///
    /// - Throws: Whatever `FileManager` raises when the directory cannot be created.
    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    /// The name for one report's file, for example
    /// `20260914T101500.123-diagnostic-hang-1a2b3c4d.json`.
    ///
    /// Sorting by name sorts by time, which is all ``prune()`` and the viewer need. A short
    /// random suffix keeps two reports arriving in the same millisecond apart.
    ///
    /// - Parameters:
    ///   - kind: Which stream the report came from.
    ///   - label: What is inside.
    ///   - date: When it arrived.
    /// - Returns: The file name.
    private func fileName(kind: Kind, label: String?, at date: Date) -> String {
        let stamp = date.formatted(Self.stamp)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return [stamp, kind.rawValue, label, suffix].compactMap(\.self).joined(separator: "-") + ".json"
    }

    /// `yyyyMMddTHHmmss.SSS` in UTC, which is what makes file names sort by time.
    private static let stamp = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .gmt, calendar: Calendar(identifier: .gregorian))
}

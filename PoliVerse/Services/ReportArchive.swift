import Foundation
import MetricKit
import OSLog

/// Keeps what MetricKit delivers, on the device, for as long as it is useful.
///
/// MetricKit hands each report over once. The old launch logger read the
/// launch histogram out of it and let the rest go — every crash, hang and
/// disk-write report included — so the only record of a field problem was a
/// log line nobody was streaming. Here each report becomes a file.
///
/// One file per report, written once and never updated, so a single atomic
/// write is the whole cost. Caps on count and size keep a phone that hangs
/// every day from filling up with evidence of it; the oldest go first.
///
/// Application Support, not the app group: the widget has no use for these,
/// and `OfflineStore` is the student's data, wiped on sign-out. Diagnostics
/// are neither, and must not be mistaken for account data or lost with it.
/// Nothing here is sent anywhere — see `docs/metrickit-performance.md` §1.10.
actor ReportArchive {
    nonisolated enum Kind: String, Sendable {
        case metric, diagnostic
    }

    nonisolated struct Entry: Sendable, Identifiable, Hashable {
        let url: URL
        let kind: Kind
        let bytes: Int
        let date: Date
        var id: URL { url }
    }

    nonisolated struct Summary: Sendable, Equatable {
        let metricCount: Int
        let diagnosticCount: Int
        let bytes: Int
        let latest: Date?
    }

    static let shared = ReportArchive()

    private let directory: URL
    private let maxFiles: Int
    private let maxBytes: Int
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "metrics")

    init(directory: URL? = nil, maxFiles: Int = 60, maxBytes: Int = 5_000_000) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("MetricKit", isDirectory: true)
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
    }

    /// Stores a report already in JSON: the iOS 26 path, from
    /// `jsonRepresentation()`. `label` names what is inside — `crash`, `hang`
    /// — and ends up in the file name, so a directory listing reads as a log.
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

    /// iOS 27. Encoded here rather than where it arrives: a day's report is
    /// real work, and nothing on screen is waiting for it.
    @available(iOS 27, *)
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

    @available(iOS 27, *)
    func store(_ report: DiagnosticReport) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            store(json: try encoder.encode(report), kind: .diagnostic, label: Self.label(for: report.result))
        } catch {
            log.error("Could not encode diagnostic report: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(iOS 27, *)
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

    /// Newest first.
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

    func summary() -> Summary {
        let all = entries()
        return Summary(
            metricCount: all.count { $0.kind == .metric },
            diagnosticCount: all.count { $0.kind == .diagnostic },
            bytes: all.reduce(0) { $0 + $1.bytes },
            latest: all.first?.date)
    }

    func removeAll() {
        for entry in entries() {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// Oldest first, until both caps hold. Names sort by time, so this reads
    /// no file metadata beyond the sizes it has to add up.
    func prune() {
        var all = entries()
        var total = all.reduce(0) { $0 + $1.bytes }
        while let oldest = all.last, all.count > maxFiles || total > maxBytes {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
            all.removeLast()
        }
    }

    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    /// `20260914T101500.123-diagnostic-hang-1a2b3c4d.json`: sorting by name
    /// sorts by time, which is all `prune()` and the viewer need.
    private func fileName(kind: Kind, label: String?, at date: Date) -> String {
        let stamp = date.formatted(Self.stamp)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return [stamp, kind.rawValue, label, suffix].compactMap(\.self).joined(separator: "-") + ".json"
    }

    private static let stamp = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .gmt, calendar: Calendar(identifier: .gregorian))
}

import Foundation
import Testing
@testable import PoliVerse

/// The archive is the only thing standing between a field crash report and
/// nothing: MetricKit hands each one over once. These pin down that it keeps
/// what arrives, and that its caps throw away the oldest, never the newest.
@Suite("Report archive")
struct ReportArchiveTests {
    private func archive(maxFiles: Int = 60, maxBytes: Int = 5_000_000) -> ReportArchive {
        ReportArchive(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("reports-\(UUID().uuidString)", isDirectory: true),
            maxFiles: maxFiles, maxBytes: maxBytes)
    }

    private func blob(_ size: Int = 10) -> Data {
        Data(repeating: UInt8(ascii: "a"), count: size)
    }

    @Test("A stored report can be listed and counted by kind")
    func storesAndSummarises() async {
        let archive = archive()
        await archive.store(json: blob(), kind: .metric)
        await archive.store(json: blob(), kind: .diagnostic, label: "hang")

        let summary = await archive.summary()
        #expect(summary.metricCount == 1)
        #expect(summary.diagnosticCount == 1)
        #expect(summary.bytes == 20)

        let hang = await archive.entries().first { $0.kind == .diagnostic }
        #expect(hang?.url.lastPathComponent.contains("-diagnostic-hang-") == true)
    }

    @Test("Past the file cap, the oldest reports go first")
    func prunesOldestByCount() async {
        let archive = archive(maxFiles: 60)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<70 {
            await archive.store(json: blob(), kind: .metric, receivedAt: start.addingTimeInterval(Double(i)))
        }

        let entries = await archive.entries()
        #expect(entries.count == 60)
        // Newest first; the ten earliest seconds are the ones gone.
        let names = entries.map(\.url.lastPathComponent)
        #expect(names.first?.hasPrefix("20270115T080109") == true)
        #expect(names.last?.hasPrefix("20270115T080010") == true)
    }

    @Test("Past the byte cap, the oldest reports go first")
    func prunesOldestBySize() async {
        let archive = archive(maxBytes: 250)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<5 {
            await archive.store(json: blob(100), kind: .diagnostic, receivedAt: start.addingTimeInterval(Double(i)))
        }

        let summary = await archive.summary()
        #expect(summary.diagnosticCount == 2)
        #expect(summary.bytes == 200)
    }

    @Test("Delete all leaves nothing behind")
    func removesAll() async {
        let archive = archive()
        await archive.store(json: blob(), kind: .metric)
        await archive.removeAll()
        #expect(await archive.entries().isEmpty)
    }
}

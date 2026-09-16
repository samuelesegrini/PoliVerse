import Foundation
import Testing
@testable import PoliVerse

/// The audit is the only thing that decides what the storage screen *says* the
/// space is, and the two things it can get wrong are both silent: a file put
/// in the wrong group (a recording counted as "altri file", which sends a
/// student looking in the wrong place) and an unstable order (the hero icon
/// swapping between two kinds of the same size on every appearance).
@Suite("Archiviazione")
struct StorageAuditTests {
    /// A folder of its own, so the test never reads the machine's real
    /// Application Support and never depends on what is downloaded there.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, bytes: Int, into directory: URL) throws {
        try Data(repeating: 0, count: bytes)
            .write(to: directory.appendingPathComponent(name))
    }

    // MARK: Which group a file lands in

    @Test("Riconosce il tipo dal sistema, non dall’estensione a mano",
          arguments: [
            ("lezione.pdf", StorageAudit.Kind.pdf),
            ("slide.pptx", .presentation),
            ("slide.key", .presentation),
            ("voti.xlsx", .spreadsheet),
            ("voti.csv", .spreadsheet),
            ("registrazione.mp4", .video),
            ("registrazione.mov", .video),
            ("podcast.m4a", .audio),
            ("lavagna.heic", .image),
            ("materiale.zip", .archive),
            ("esercizio.swift", .code),
            ("appunti.docx", .document),
            ("appunti.txt", .document),
            ("materiale.qqq", .other),
            ("senzaestensione", .other),
          ])
    func classifies(name: String, expected: StorageAudit.Kind) {
        #expect(StorageAudit.Kind.of(URL(filePath: "/tmp/\(name)")) == expected)
    }

    /// The order the checks run in is load-bearing: a `.csv` is also plain
    /// text and a `.key` is also a package, so whichever conforms first wins.
    /// Getting this backwards files every spreadsheet under "Documenti".
    @Test("Un csv è un foglio di calcolo, non un documento")
    func csvIsASpreadsheet() {
        #expect(StorageAudit.Kind.of(URL(filePath: "/tmp/voti.csv")) == .spreadsheet)
    }

    // MARK: What the scan reports

    @Test("Raggruppa per tipo e mette il più grande per primo")
    func groupsAndSorts() throws {
        let materials = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: materials) }

        try write("uno.pdf", bytes: 1_000, into: materials)
        try write("due.pdf", bytes: 2_000, into: materials)
        try write("lezione.mp4", bytes: 9_000, into: materials)

        let categories = StorageAudit.scanNow(materials: [materials], appData: [])

        #expect(categories.map(\.kind) == [.video, .pdf])
        #expect(categories[0].bytes == 9_000)
        #expect(categories[1].bytes == 3_000)
        #expect(categories[1].fileCount == 2)
        #expect(categories.totalBytes == 12_000)
    }

    /// Two kinds of exactly the same size must come back the same way twice:
    /// the screen draws the first one as a large icon, and one that changes
    /// on every visit reads as a fault.
    @Test("A parità di dimensione l’ordine non cambia fra due letture")
    func orderIsStable() throws {
        let materials = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: materials) }

        try write("a.pdf", bytes: 4_000, into: materials)
        try write("b.mp4", bytes: 4_000, into: materials)
        try write("c.zip", bytes: 4_000, into: materials)

        let first = StorageAudit.scanNow(materials: [materials], appData: [])
        for _ in 0..<8 {
            #expect(StorageAudit.scanNow(materials: [materials], appData: []).map(\.kind)
                    == first.map(\.kind))
        }
    }

    /// The app's own JSON is one row whatever it is made of: nobody needs to
    /// know that the libretto's file is 40 kB and the timetable's is 60.
    @Test("I dati dell’app contano come una sola voce")
    func appDataIsOneCategory() throws {
        let cache = try makeDirectory()
        let offline = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: cache)
            try? FileManager.default.removeItem(at: offline)
        }

        try write("corsi.json", bytes: 500, into: cache)
        try write("orario.json", bytes: 700, into: offline)

        let categories = StorageAudit.scanNow(materials: [], appData: [cache, offline])

        #expect(categories.count == 1)
        #expect(categories[0].kind == .appData)
        #expect(categories[0].bytes == 1_200)
        #expect(categories[0].fileCount == 2)
        #expect(categories.materialBytes == 0)
    }

    @Test("Una cartella che non esiste non è un errore")
    func missingFoldersAreEmpty() {
        let absent = URL(filePath: "/tmp/poliverse-non-esiste-\(UUID().uuidString)")
        #expect(StorageAudit.scanNow(materials: [absent], appData: [absent]).isEmpty)
    }

    // MARK: Removing

    /// The screen reports what it freed, and that number has to be the bytes
    /// that actually went — not the bytes it measured a moment earlier.
    @Test("Eliminare una voce libera esattamente quei byte")
    func deleteReportsWhatWentAway() throws {
        let materials = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: materials) }

        try write("uno.pdf", bytes: 1_500, into: materials)
        try write("lezione.mp4", bytes: 6_000, into: materials)

        let before = StorageAudit.scanNow(materials: [materials], appData: [])
        let pdfs = try #require(before.first { $0.kind == .pdf })

        #expect(StorageAudit.delete(pdfs) == 1_500)

        let after = StorageAudit.scanNow(materials: [materials], appData: [])
        #expect(after.map(\.kind) == [.video])
        #expect(after.totalBytes == 6_000)
    }
}

import Foundation
import Testing
import UIKit
@testable import PoliVerse

/// Finding the student's own line in a teacher's results file — and nothing
/// else.
///
/// The file lists other students. What comes out of it is deliberately tiny:
/// whether it looks like results, whether the student is in it, and their own
/// mark. Everything here is about getting those three right without ever
/// reading someone else's row as theirs.
@Suite("Results file reader")
struct ResultsFileReaderTests {
    private let me = ["987654", "10765432"]

    private let table = """
    Esiti appello del 31/08/2026
    Matricola  Cognome  Nome  Voto
    912345  Bianchi  Anna  30 e lode
    923456  Verdi  Luca  Insufficiente
    987654  Rossi  Mario  27
    934567  Neri  Sara  18
    945678  Gialli  Piero  Ritirato
    """

    @Test("The student's own mark is read off their line")
    func ownLine() {
        let lookup = ResultsFileReader.lookup(text: table, identifiers: me)
        #expect(lookup == ResultsLookup(looksLikeResults: true, found: true, grade: "27"))
    }

    /// One digit of difference is another student.
    @Test("Only an exact identifier matches, never a longer number containing it")
    func exact() {
        let text = table.replacingOccurrences(of: "987654  Rossi", with: "9876541  Rossi")
        let lookup = ResultsFileReader.lookup(text: text, identifiers: me)
        #expect(lookup.found == false)
        #expect(lookup.grade == nil)
    }

    @Test("Not in the file is a valid answer, not an error")
    func absent() {
        let lookup = ResultsFileReader.lookup(text: table, identifiers: ["111111"])
        #expect(lookup == ResultsLookup(looksLikeResults: true, found: false, grade: nil))
    }

    @Test("Marks in words, with honours, and alongside dates", arguments: [
        ("987654 Rossi Mario 30 e lode", "30L"),
        ("987654 Rossi Mario 30L", "30L"),
        ("987654;Rossi;Mario;Insufficiente", "Insufficiente"),
        ("987654,Rossi,Mario,ritirato", "Ritirato"),
        ("987654 Rossi Mario NON AMMESSO", "Non ammesso"),
        ("987654 Rossi Mario ammesso all'orale", "Ammesso"),
        ("987654\tRossi\t31/08/2026\t24", "24"),
        ("10765432 Rossi Mario 25,5", "25,5"),
        ("987654 Rossi Mario 27/30", "27"),
        ("987654 Rossi 12.07.2026 ore 10:30 26", "26"),
        ("987654,Rossi,Mario,24", "24"),
        ("987654 Rossi RIT", "Ritirato"),
        ("987654 Rossi N.C.", "Non classificato"),
    ])
    func grades(_ line: String, _ expected: String) {
        let alone = (1...5).map { "91000\($0) X 20" }.joined(separator: "\n") + "\n" + line
        #expect(ResultsFileReader.lookup(text: alone, identifiers: me).grade == expected)
    }

    /// "Risultati: l'orale si terrà il…" is a notice with a results word in
    /// its name.
    @Test("A file with no table of identifiers does not look like results")
    func notATable() {
        let lookup = ResultsFileReader.lookup(
            text: "Risultati: gli orali si terranno il 12/09 in aula B.3.2. Esercizio 1: si ottiene 27.",
            identifiers: me)
        #expect(lookup == ResultsLookup(looksLikeResults: false, found: false, grade: nil))
    }

    @Test("Identifiers too short to be one are ignored")
    func shortIdentifiers() {
        #expect(ResultsFileReader.lookup(text: table, identifiers: ["", "27"]).found == false)
    }

    @Test("Plain text and CSV are read as text; unknown binary is not")
    func extraction() {
        let csv = Data("987654;Rossi;27".utf8)
        #expect(ResultsFileReader.text(from: csv, mimetype: "text/csv", fileName: "esiti.csv") == "987654;Rossi;27")
        #expect(ResultsFileReader.text(from: Data([0xFF, 0xD8, 0xFF]), mimetype: "image/jpeg", fileName: "foto.jpg") == nil)
        #expect(ResultsFileReader.text(from: Data([0x50, 0x4B]), mimetype: nil, fileName: "esiti.xlsx") == nil)
    }

    /// A two-column PDF puts two students on one text line.
    @Test("Another student's row on the same line is never read as the student's")
    func twoColumns() {
        let rows = (1...5).map { "91000\($0) X 20" }.joined(separator: "\n")
        let line = "987654 Rossi 27   934567 Neri Ritirato"
        #expect(ResultsFileReader.lookup(text: rows + "\n" + line, identifiers: me).grade == "27")
        let other = "934567 Neri 18   987654 Rossi"
        #expect(ResultsFileReader.lookup(text: rows + "\n" + other, identifiers: me).grade == nil)
    }

    /// A score and a mark, or a mark and the credits: not guessed between.
    @Test("Two different numbers in the student's cells leave the mark unknown")
    func ambiguousNumbers() {
        let rows = (1...5).map { "91000\($0) X 20" }.joined(separator: "\n")
        let lookup = ResultsFileReader.lookup(text: rows + "\n987654 Rossi 22 8", identifiers: me)
        #expect(lookup.found)
        #expect(lookup.grade == nil)
    }

    @Test("A synthetic PDF with a text layer is read")
    func pdf() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = renderer.pdfData { context in
            context.beginPage()
            (table as NSString).draw(in: CGRect(x: 20, y: 20, width: 560, height: 760),
                                     withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
        let text = try #require(ResultsFileReader.text(from: data, mimetype: "application/pdf", fileName: "esiti.pdf"))
        #expect(ResultsFileReader.lookup(text: text, identifiers: me).found)
    }
}

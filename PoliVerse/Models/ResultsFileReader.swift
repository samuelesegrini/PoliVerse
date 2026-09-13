import Foundation
import PDFKit

/// What a results file says about the student — and only about them.
///
/// Stored with the update, so it is deliberately all the file leaves behind:
/// no other row, no count, no average. See
/// `docs/academic-intelligence-layer.md` §10.4.
nonisolated struct ResultsLookup: Sendable, Equatable, Codable {
    /// A table of student identifiers, rather than a notice with "risultati"
    /// in its name.
    let looksLikeResults: Bool
    /// The student's matricola or person code is on a line of it.
    let found: Bool
    /// The mark on that line, as written. Unconfirmed until the exam services
    /// publish it; they win any disagreement.
    let grade: String?
}

/// Reads a teacher's results file for the student's own line.
///
/// Pure over text, so the rules are tested without files. The text itself
/// lives only for the duration of a call: nothing here stores it, logs it,
/// or looks at any line but the student's.
nonisolated enum ResultsFileReader {
    /// A results table lists at least this many distinct identifiers.
    static let minimumRows = 5
    /// Files larger than this are not read: a results list is small, and a
    /// background pass has seconds, not minutes.
    static let maximumBytes = 5_000_000

    static func lookup(text: String, identifiers: [String]) -> ResultsLookup {
        let lines = text.components(separatedBy: .newlines).map(cells)

        var seen: Set<String> = []
        for line in lines {
            seen.formUnion(matches(identifier, in: line))
            if seen.count >= minimumRows { break }
        }
        let looksLikeResults = seen.count >= minimumRows

        let mine = identifiers.filter { $0.count >= 6 && $0.allSatisfy(\.isNumber) }
        for line in lines {
            for id in mine {
                guard let range = line.range(of: #"(?<!\d)\#(id)(?!\d)"#, options: .regularExpression)
                else { continue }
                // Only up to the next identifier: a PDF laid out in two
                // columns puts another student's row on the same line.
                var rest = String(line[range.upperBound...])
                if let next = rest.range(of: identifier, options: .regularExpression) {
                    rest = String(rest[..<next.lowerBound])
                }
                return ResultsLookup(looksLikeResults: looksLikeResults, found: true, grade: grade(in: rest))
            }
        }
        return ResultsLookup(looksLikeResults: looksLikeResults, found: false, grade: nil)
    }

    private static let identifier = #"(?<!\d)(\d{6}|\d{8})(?!\d)"#

    /// One line with its cell separators as spaces.
    ///
    /// Semicolons, tabs and bars always separate. A comma separates when the
    /// line uses commas as its delimiter — two or more outside numbers —
    /// and otherwise, between digits, is an Italian decimal: "25,5".
    private static func cells(_ line: String) -> String {
        let delimiterCommas = matches(#"(?<!\d),|,(?!\d)"#, in: line).count
        let commas = delimiterCommas >= 2 ? #","# : #"(?<!\d),|,(?!\d)"#
        return line.replacingOccurrences(of: #"[;\t|]|"# + commas, with: " ", options: .regularExpression)
    }

    /// The mark in the student's own cells, or nil when it cannot be told
    /// apart from anything else there.
    ///
    /// Words first — "Insufficiente 14" is insufficient, not fourteen — then
    /// honours and "27/30", then a number that can be a mark. Dates and times
    /// are removed first. Two different candidate numbers (a score and a
    /// mark, a mark and CFU) are not guessed between: found, mark unknown.
    private static func grade(in rest: String) -> String? {
        var folded = rest.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        folded = folded
            .replacingOccurrences(of: #"\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{1,2}:\d{2}\b"#, with: " ", options: .regularExpression)

        let words: [(String, String)] = [
            (#"\bnon ammess[oa]\b"#, String(localized: "Non ammesso")),
            (#"\binsuff\w*"#, String(localized: "Insufficiente")),
            (#"\b(ritirat[oa]|rit)\b"#, String(localized: "Ritirato")),
            (#"\b(assente|ass)\b"#, String(localized: "Assente")),
            (#"\brespint[oa]\b"#, String(localized: "Respinto")),
            (#"(\bn\.\s?c\.|\bnc\b|non classificat[oa])"#, String(localized: "Non classificato")),
            (#"\bammess[oa]\b"#, String(localized: "Ammesso")),
            (#"\bsuperat[oa]\b"#, String(localized: "Superato")),
            (#"\bidone[oa]\b"#, String(localized: "Idoneo")),
        ]
        for (pattern, label) in words where folded.range(of: pattern, options: .regularExpression) != nil {
            return label
        }
        if folded.range(of: #"\b30\s*(e\s*lode|l)\b"#, options: .regularExpression) != nil { return "30L" }
        if let outOf30 = matches(#"(?<!\d)([0-9]|[12][0-9]|30)\s*/\s*30(?!\d)"#, in: folded).first {
            return outOf30.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces)
        }

        let number = #"(?<![\d/.\-])([0-9]|[12][0-9]|3[0-1])([.,][0-9]{1,2})?(?![\d/.\-]|[.,]\d)"#
        let candidates = Set(matches(number, in: folded))
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Every match of an ICU pattern. ICU rather than `Regex`: the rules need
    /// lookbehind, which Swift's engine does not support.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// The text of a downloaded file, for the formats that can be read without
    /// a third-party library: PDF with a text layer, CSV, plain text.
    ///
    /// A scanned PDF has no text layer and yields nothing — the update stays
    /// a plain "results file posted". Spreadsheets likewise, until reading
    /// them is worth a dependency.
    /// Reads and looks up away from the main actor: a PDF of a few megabytes
    /// takes long enough to drop frames.
    static func read(_ data: Data, mimetype: String?, fileName: String, identifiers: [String]) async -> ResultsLookup? {
        await Task.detached(priority: .utility) {
            text(from: data, mimetype: mimetype, fileName: fileName)
                .map { lookup(text: $0, identifiers: identifiers) }
        }.value
    }

    static func text(from data: Data, mimetype: String?, fileName: String) -> String? {
        guard data.count <= maximumBytes else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if mimetype == "application/pdf" || ext == "pdf" {
            return PDFDocument(data: data)?.string
        }
        if ["csv", "txt"].contains(ext) || mimetype?.hasPrefix("text/") == true {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        return nil
    }
}

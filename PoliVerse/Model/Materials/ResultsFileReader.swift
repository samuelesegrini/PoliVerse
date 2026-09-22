import Foundation
import PDFKit

/// What a results file said about the student, and only about them.
///
/// Stored alongside the update, and deliberately all the file leaves behind: no other
/// row, no count, no average. See `docs/academic-intelligence-layer.md` §10.4.
nonisolated struct ResultsLookup: Sendable, Equatable, Codable {
    /// Whether the file is a table of student identifiers, rather than a notice that
    /// merely has “risultati” in its name.
    let looksLikeResults: Bool
    /// Whether the student's own matricola or person code appears on a line.
    let found: Bool
    /// What was written on that line, as written.
    ///
    /// Unconfirmed until the exam services publish the mark, and they win any
    /// disagreement. `nil` when the line carries nothing that can be told apart from
    /// anything else on it.
    let grade: String?
}

/// Reads a lecturer's results file for the student's own line.
///
/// Pure over text, so the rules can be tested without files. The text lives only for
/// the duration of a call: nothing here stores it, logs it, or looks at any line but
/// the student's.
nonisolated enum ResultsFileReader {
    /// How many distinct identifiers a file must carry before it counts as a results
    /// table.
    static let minimumRows = 5
    /// The largest file that will be read. A results list is small, and a background pass
    /// has seconds rather than minutes.
    static let maximumBytes = 5_000_000

    /// Looks for the student's own line in a file's text.
    ///
    /// Only the part of the line after the student's identifier is read, and only up to
    /// the next identifier — a PDF laid out in two columns puts another student's row on
    /// the same line.
    ///
    /// - Parameters:
    ///   - text: The file's text.
    ///   - identifiers: The student's matricola and person code. Only six- and
    ///     eight-digit numeric values are used.
    /// - Returns: What the file said.
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

    /// A student identifier: a six- or eight-digit number not adjacent to other digits.
    private static let identifier = #"(?<!\d)(\d{6}|\d{8})(?!\d)"#

    /// One line with its cell separators turned into spaces.
    ///
    /// Semicolons, tabs and bars always separate. A comma separates when the line uses
    /// commas as its delimiter — two or more outside numbers — and otherwise, between
    /// digits, is an Italian decimal point.
    ///
    /// - Parameter line: The line as read.
    /// - Returns: The line with separators normalised.
    private static func cells(_ line: String) -> String {
        let delimiterCommas = matches(#"(?<!\d),|,(?!\d)"#, in: line).count
        let commas = delimiterCommas >= 2 ? #","# : #"(?<!\d),|,(?!\d)"#
        return line.replacingOccurrences(of: #"[;\t|]|"# + commas, with: " ", options: .regularExpression)
    }

    /// The mark in the student's own cells.
    ///
    /// Dates and times are removed first. Words win over numbers, so “Insufficiente 14”
    /// is insufficient rather than fourteen, and the earliest word on the line wins, with
    /// the more specific rule preferred at the same position. Honours and `27/30` are
    /// then recognised, and finally a bare number that could be a mark.
    ///
    /// Two different candidate numbers — a raw score and a mark, or a mark and a credit
    /// count — are not guessed between.
    ///
    /// - Parameter rest: The student's cells.
    /// - Returns: The mark as written, or `nil` when it cannot be told apart.
    private static func grade(in rest: String) -> String? {
        var folded = rest.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        folded = folded
            .replacingOccurrences(of: #"\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{1,2}:\d{2}\b"#, with: " ", options: .regularExpression)

        // Italian and English: English-taught courses publish English lists.
        // Negations before what they negate, and the earliest word on the
        // line wins: "Passed (failed first attempt)" passed.
        let words: [(String, String)] = [
            (#"\b(non ammess[oa]|not admitted)\b"#, String(localized: "Non ammesso")),
            (#"\b(non superat[oa]|not passed)\b"#, String(localized: "Insufficiente")),
            (#"\b(insuff\w*|fail(ed)?)\b"#, String(localized: "Insufficiente")),
            (#"\b(ritirat[oa]|rit|withdrawn)\b"#, String(localized: "Ritirato")),
            (#"\b(assente|ass|absent)\b"#, String(localized: "Assente")),
            (#"\b(respint[oa]|rejected)\b"#, String(localized: "Respinto")),
            (#"(\bn\.\s?c\.|\bnc\b|non classificat[oa]|not graded)"#, String(localized: "Non classificato")),
            (#"\b(ammess[oa]|admitted)\b"#, String(localized: "Ammesso")),
            (#"\b(superat[oa]|passed)\b"#, String(localized: "Superato")),
            (#"\bidone[oa]\b"#, String(localized: "Idoneo")),
        ]
        let hits = words.enumerated().compactMap { index, word -> (String.Index, Int, String)? in
            folded.range(of: word.0, options: .regularExpression).map { ($0.lowerBound, index, word.1) }
        }
        // Earliest on the line; at the same position, the more specific rule
        // (listed first) — "not passed" over "passed".
        if let first = hits.min(by: { ($0.0, $0.1) < ($1.0, $1.1) }) { return first.2 }
        if folded.range(of: #"\b30\s*(e\s*lode|l|cum laude|with honou?rs)\b"#, options: .regularExpression) != nil {
            return "30L"
        }
        if let outOf30 = matches(#"(?<!\d)([0-9]|[12][0-9]|30)\s*/\s*30(?!\d)"#, in: folded).first {
            return outOf30.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces)
        }

        let number = #"(?<![\d/.\-])([0-9]|[12][0-9]|3[0-1])([.,][0-9]{1,2})?(?![\d/.\-]|[.,]\d)"#
        let candidates = Set(matches(number, in: folded))
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Every match of an ICU pattern.
    ///
    /// ICU rather than `Regex`, because these rules need lookbehind.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern.
    ///   - text: The text to search.
    /// - Returns: The matched substrings, in order.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = RegexCache.regex(pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// Reads a downloaded file and looks the student up in it, off the main actor.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - mimetype: The file's media type, where known.
    ///   - fileName: The file's name, whose extension is used when there is no media type.
    ///   - identifiers: The student's matricola and person code.
    /// - Returns: What the file said, or `nil` when it cannot be read.
    static func read(_ data: Data, mimetype: String?, fileName: String, identifiers: [String]) async -> ResultsLookup? {
        await Task.detached(priority: .utility) {
            text(from: data, mimetype: mimetype, fileName: fileName)
                .map { lookup(text: $0, identifiers: identifiers) }
        }.value
    }

    /// The text of a file, for the formats readable without a third-party library: PDF
    /// with a text layer, CSV and plain text.
    ///
    /// A scanned PDF has no text layer and yields nothing, which leaves the update a plain
    /// posting. Spreadsheets are not read.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - mimetype: The file's media type, where known.
    ///   - fileName: The file's name, whose extension is used when there is no media type.
    /// - Returns: The text, or `nil` for a file too large or of an unreadable format.
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

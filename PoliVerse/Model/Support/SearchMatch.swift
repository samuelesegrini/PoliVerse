import Foundation

/// How a query is compared to text, and how well.
///
/// One rule, in one place, so every kind of result is matched and ranked the
/// same way. `localizedCaseInsensitiveContains` used to do this per call site,
/// which was wrong twice over: it misses a word typed without its accent, and
/// it cannot tell a title that *starts* with the query from one that merely
/// contains it, so "ana" put "Metodi Analitici" above "Analisi".
nonisolated enum SearchMatch {
    /// Case- and diacritic-insensitive, so "citta" finds "Città" and
    /// "informatica" finds "Informàtici".
    private static let options: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive,
    ]

    static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every word of the query appears somewhere in the fields.
    ///
    /// Word-wise rather than as one substring: "basi dati" should find "Basi
    /// di Dati", which a single `contains` never will.
    static func matches(_ query: String, in fields: String?...) -> Bool {
        matches(query, fields: fields.compactMap { $0 })
    }

    static func matches(_ query: String, fields: [String]) -> Bool {
        let words = words(in: query)
        guard !words.isEmpty else { return false }
        let haystack = fields.joined(separator: " ")
        return words.allSatisfy { haystack.range(of: $0, options: options) != nil }
    }

    /// How good a match is. Zero means no match; higher is better.
    ///
    /// The ladder, highest first: the whole field equals the query, the field
    /// starts with it, a word inside starts with it, it appears anywhere.
    /// Ties are broken by how much of the field the query accounts for, so a
    /// short precise title beats a long one that happens to contain the word.
    static func score(_ query: String, in fields: String?...) -> Int {
        score(query, fields: fields.compactMap { $0 })
    }

    static func score(_ query: String, fields: [String]) -> Int {
        let words = words(in: query)
        guard !words.isEmpty, matches(query, fields: fields) else { return 0 }

        var best = 0
        for field in fields where !field.isEmpty {
            let whole = query.trimmingCharacters(in: .whitespaces)
            if field.compare(whole, options: options) == .orderedSame {
                best = max(best, 1000)
            } else if field.range(of: whole, options: [options, .anchored]) != nil {
                best = max(best, 500)
            } else if startsAWord(whole, in: field) {
                best = max(best, 250)
            } else if field.range(of: whole, options: options) != nil {
                best = max(best, 100)
            } else {
                // Every word present but not adjacent — still a match, and
                // the weakest kind.
                best = max(best, 50)
            }

            // Shorter fields are more specific; worth a nudge, never enough to
            // cross a rung of the ladder above.
            if best > 0 {
                best += max(0, 40 - field.count / 4)
            }
        }
        return best
    }

    private static func startsAWord(_ query: String, in field: String) -> Bool {
        field.split(whereSeparator: { $0.isWhitespace || $0 == "'" || $0 == "\u{2019}" })
            .contains { $0.range(of: query, options: [options, .anchored]) != nil }
    }

    /// Filters to what matches and orders by score, then alphabetically so the
    /// list is stable between keystrokes that do not change the ranking.
    static func rank<T>(
        _ items: [T], query: String, fields: (T) -> [String]
    ) -> [T] {
        items
            .map { (item: $0, score: score(query, fields: fields($0))) }
            .filter { $0.score > 0 }
            .sorted {
                $0.score == $1.score
                    ? (fields($0.item).first ?? "") < (fields($1.item).first ?? "")
                    : $0.score > $1.score
            }
            .map(\.item)
    }

    static func rank<T>(
        _ items: [T], query: String, field: @escaping (T) -> String
    ) -> [T] {
        rank(items, query: query) { [field($0)] }
    }
}

import Foundation

/// How a query is compared to text, and how well it matches.
///
/// One rule for every kind of result, so courses, rooms, teachers and exams are
/// matched and ranked alike. Comparison ignores case and diacritics, matching is
/// word-wise rather than by substring, and ``score(_:fields:)`` ranks a field that
/// begins with the query above one that merely contains it.
nonisolated enum SearchMatch {
    /// Case-, diacritic- and width-insensitive, so `"citta"` finds `"Città"`.
    private static let options: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive,
    ]

    /// Splits a query on whitespace.
    ///
    /// - Parameter query: What the student typed.
    /// - Returns: The words, in order. Empty for a blank query.
    static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every word of the query appears somewhere in the given fields.
    ///
    /// - Parameters:
    ///   - query: What the student typed.
    ///   - fields: The fields to search. `nil` fields are ignored.
    /// - Returns: `true` when every word is found. `false` for a blank query.
    static func matches(_ query: String, in fields: String?...) -> Bool {
        matches(query, fields: fields.compactMap { $0 })
    }

    /// Whether every word of the query appears somewhere in the given fields.
    ///
    /// The fields are joined before searching, so words may be spread across them:
    /// `"basi dati"` matches `"Basi di Dati"`, which no single substring search would.
    ///
    /// - Parameters:
    ///   - query: What the student typed.
    ///   - fields: The fields to search.
    /// - Returns: `true` when every word is found. `false` for a blank query.
    static func matches(_ query: String, fields: [String]) -> Bool {
        let words = words(in: query)
        guard !words.isEmpty else { return false }
        let haystack = fields.joined(separator: " ")
        return words.allSatisfy { haystack.range(of: $0, options: options) != nil }
    }

    /// How well a query matches, as a number.
    ///
    /// - Parameters:
    ///   - query: What the student typed.
    ///   - fields: The fields to search. `nil` fields are ignored.
    /// - Returns: Zero for no match; higher is better.
    static func score(_ query: String, in fields: String?...) -> Int {
        score(query, fields: fields.compactMap { $0 })
    }

    /// How well a query matches, as a number.
    ///
    /// The best-scoring field decides, on this ladder: the whole field equals the
    /// query (1000), the field begins with it (500), a word inside it begins with it
    /// (250), it appears anywhere (100), or every word is present but not adjacent
    /// (50). A shorter field then earns a bonus of up to 40, never enough to cross a
    /// rung, so a short precise title outranks a long one containing the same word.
    ///
    /// - Parameters:
    ///   - query: What the student typed.
    ///   - fields: The fields to search.
    /// - Returns: Zero when the query does not match; higher is better.
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

    /// Whether any word of the field begins with the query.
    ///
    /// Words are split on whitespace and on both apostrophe forms, so `"ing"` begins a
    /// word in `"dell'Ingegneria"`.
    ///
    /// - Parameters:
    ///   - query: What the student typed.
    ///   - field: The field to search.
    /// - Returns: `true` when a word begins with the query.
    private static func startsAWord(_ query: String, in field: String) -> Bool {
        field.split(whereSeparator: { $0.isWhitespace || $0 == "'" || $0 == "\u{2019}" })
            .contains { $0.range(of: query, options: [options, .anchored]) != nil }
    }

    /// Filters items to those that match and orders them best first.
    ///
    /// Equal scores are broken alphabetically on the first field, so the list is stable
    /// between keystrokes that do not change the ranking.
    ///
    /// - Parameters:
    ///   - items: The candidates.
    ///   - query: What the student typed.
    ///   - fields: The searchable fields of one item.
    /// - Returns: The matching items, best first.
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

    /// Filters items to those that match one field and orders them best first.
    ///
    /// - Parameters:
    ///   - items: The candidates.
    ///   - query: What the student typed.
    ///   - field: The searchable field of one item.
    /// - Returns: The matching items, best first.
    static func rank<T>(
        _ items: [T], query: String, field: @escaping (T) -> String
    ) -> [T] {
        rank(items, query: query) { [field($0)] }
    }
}

import Foundation

/// The HTML reading the Manifesti degli Studi service needs.
///
/// That service answers HTML rather than JSON and has no API behind it. This type
/// reads the three structures its pages use — label/value cards, tables and links —
/// with regular expressions over ``RegexCache``.
///
/// - Important: This is not an HTML parser and must not be extended into one. It
///   works because the markup is template-generated and therefore regular. Markup
///   that requires real nesting needs a parser instead.
nonisolated enum HTMLScraper {
    /// A fragment as plain text: tags stripped, entities decoded, whitespace
    /// collapsed.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The readable text. See ``HTMLText/plain(_:)``.
    static func text(_ html: String) -> String {
        HTMLText.plain(html)
    }

    /// The value beside a label in a `BoxInfoCard` table.
    ///
    /// The markup is `<td class="ElementInfoCard1">Label</td>` followed by
    /// `<td class="ElementInfoCard2">Value</td>`, which is how every field on a
    /// teaching page is expressed.
    ///
    /// - Parameters:
    ///   - label: The label to find, matched literally.
    ///   - html: The page or fragment to search.
    /// - Returns: The value as text, or `nil` when the label is absent or its value is
    ///   empty.
    static func cardValue(_ label: String, in html: String) -> String? {
        let pattern = """
        ElementInfoCard1[^>]*>\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*\
        </td>\\s*<td[^>]*ElementInfoCard2[^>]*>(.*?)</td>
        """
        guard let match = firstMatch(pattern, in: html, group: 1) else { return nil }
        return text(match).nonEmpty
    }

    /// Every label/value pair of a card, in document order.
    ///
    /// - Parameter html: The page or fragment to search.
    /// - Returns: The pairs as text. Pairs with an empty label are omitted.
    static func cardPairs(in html: String) -> [(label: String, value: String)] {
        let pattern = "ElementInfoCard1[^>]*>(.*?)</td>\\s*<td[^>]*ElementInfoCard2[^>]*>(.*?)</td>"
        return matches(pattern, in: html).compactMap { groups in
            guard groups.count >= 2 else { return nil }
            let label = text(groups[0]), value = text(groups[1])
            guard !label.isEmpty else { return nil }
            return (label, value)
        }
    }

    /// The rows of every table, each as its cells' raw HTML.
    ///
    /// Raw rather than text, because a cell often carries the link that identifies what
    /// it names — a teacher's `k_doc`, a module's code.
    ///
    /// - Parameter html: The page or fragment to search.
    /// - Returns: One array of cell fragments per row. Empty rows are omitted.
    static func rows(in html: String) -> [[String]] {
        matches("<tr[^>]*>(.*?)</tr>", in: html).compactMap { groups in
            guard let row = groups.first else { return nil }
            let cells = matches("<t[dh][^>]*>(.*?)</t[dh]>", in: row).compactMap(\.first)
            return cells.isEmpty ? nil : cells
        }
    }

    /// The first `href` in a fragment, with `&amp;` decoded.
    ///
    /// - Parameter html: The fragment to search.
    /// - Returns: The link, or `nil` when there is none.
    static func href(in html: String) -> String? {
        firstMatch("href=\"([^\"]+)\"", in: html, group: 1)
            .map { $0.replacingOccurrences(of: "&amp;", with: "&") }
    }

    /// A query parameter's value from a URL string, percent-decoded.
    ///
    /// Matched case-insensitively, because this service's parameter names drift in
    /// case between links.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - url: The URL string to read.
    /// - Returns: The value, or `nil` when the parameter is absent.
    static func queryValue(_ name: String, in url: String) -> String? {
        let pattern = "[?&]\(NSRegularExpression.escapedPattern(for: name))=([^&\"#]*)"
        return firstMatch(pattern, in: url, group: 1, caseInsensitive: true)?
            .removingPercentEncoding
    }

    /// Everything between a section title and the next one.
    ///
    /// Sections are announced by `<td class="TitleInfoCard">Name</td>` and run until
    /// the following title; there is no container element to scope them by.
    ///
    /// - Parameters:
    ///   - title: The section title, matched literally and case-insensitively.
    ///   - html: The page to search.
    /// - Returns: The section's markup, running to the end of the page when no further
    ///   title follows, or `nil` when the title is absent.
    static func section(_ title: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: title)
        guard let start = range(of: "TitleInfoCard[^>]*>\\s*\(escaped)", in: html) else {
            return nil
        }
        let rest = String(html[start.upperBound...])
        guard let next = range(of: "TitleInfoCard", in: rest) else { return rest }
        return String(rest[..<next.lowerBound])
    }

    // MARK: - Regex plumbing

    /// The range of the first match of a pattern.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern, matched case-insensitively.
    ///   - html: The string to search.
    /// - Returns: The matched range, or `nil`.
    private static func range(
        of pattern: String, in html: String
    ) -> Range<String.Index>? {
        html.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }

    /// One capture group of the first match of a pattern.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern. `.` spans line separators.
    ///   - html: The string to search.
    ///   - group: Which capture group to return.
    ///   - caseInsensitive: Whether to ignore case.
    /// - Returns: The captured text, or `nil` when the pattern does not compile, does
    ///   not match, or the group did not participate.
    static func firstMatch(
        _ pattern: String, in html: String, group: Int, caseInsensitive: Bool = true
    ) -> String? {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard
            let regex = RegexCache.regex(pattern, options: options),
            let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: group), in: html)
        else { return nil }
        return String(html[range])
    }

    /// Every match of a pattern, each as its capture groups.
    ///
    /// Group zero — the whole match — is omitted, so the first element is group one.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern, matched case-insensitively with `.` spanning line
    ///     separators.
    ///   - html: The string to search.
    /// - Returns: One array of captures per match. Empty when the pattern does not
    ///   compile.
    static func matches(_ pattern: String, in html: String) -> [[String]] {
        guard let regex = RegexCache.regex(
            pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .map { match in
                (1..<match.numberOfRanges).compactMap { index in
                    Range(match.range(at: index), in: html).map { String(html[$0]) }
                }
            }
    }
}

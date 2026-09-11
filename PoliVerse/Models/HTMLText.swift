import Foundation

/// Turns the HTML these endpoints send into readable plain text.
///
/// The news feed returns its description as an HTML fragment — the field
/// arrived on screen as literal `<p>` and `&egrave;`. Notifications use the
/// same backend conventions, so both go through here.
///
/// Deliberately **not** `NSAttributedString(data:options:documentType:.html)`.
/// That importer is WebKit-backed and main-actor bound: running it per row in
/// a scrolling list is a well-known source of hitches, and even in a detail
/// view it blocks the first frame. These are short announcements where
/// paragraph structure is the only formatting that carries meaning, and the
/// link out to the site is already a separate field.
nonisolated enum HTMLText {
    /// Plain text, with block structure preserved as blank lines.
    static func plain(_ html: String) -> String {
        var text = html

        // Script and style carry no reading content, and their bodies are not
        // markup — dropping tags alone would leave CSS on screen.
        text = removeElements(named: ["script", "style", "head"], from: text)

        // Block boundaries become newlines before the tags are dropped;
        // otherwise every paragraph runs into the next.
        // Line breaks are marked with a sentinel rather than a newline,
        // because the next step has to tell them apart from the newlines in
        // the *source*. HTML treats a newline inside a paragraph as a space —
        // markup is usually wrapped for readability — so the two cannot be
        // collapsed together without either losing the real breaks or turning
        // the author's line wrapping into them.
        //
        // A paragraph or heading ends with a blank line, a `<br>` with a
        // single newline. That distinction is the only formatting left once
        // the tags are gone.
        text = text.replacingOccurrences(
            of: "</p>|</div>|</h[1-6]>|</blockquote>",
            with: "\(Self.breakMark)\(Self.breakMark)",
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "<br\\s*/?>|</tr>",
            with: Self.breakMark,
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "<li[^>]*>",
            with: "\(Self.breakMark)• ",
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "</li>|</ul>|</ol>",
            with: Self.breakMark,
            options: [.regularExpression, .caseInsensitive])

        // Then every remaining tag.
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)

        // Entities last, on purpose: an encoded `&lt;b&gt;` is text the author
        // wrote, not markup, and decoding before stripping would turn it into
        // a tag and delete it.
        text = decodeEntities(text)

        return tidy(text)
    }

    /// Whether a string looks like it carries markup worth stripping.
    ///
    /// Used to keep the work off strings that are already plain — most titles
    /// are, and a regex pass per row for nothing is waste.
    static func containsMarkup(_ string: String) -> Bool {
        string.range(of: "<[^>]+>|&[#a-zA-Z][a-zA-Z0-9]{1,9};",
                     options: .regularExpression) != nil
    }

    /// Strips markup only when there is some, so a plain string is returned
    /// untouched and uncopied.
    static func plainIfNeeded(_ string: String) -> String {
        containsMarkup(string) ? plain(string) : string
    }

    private static func removeElements(named names: [String], from html: String) -> String {
        names.reduce(html) { partial, name in
            partial.replacingOccurrences(
                // `(?s)` so `.` spans newlines: a <style> block is almost
                // always written across several lines.
                of: "(?s)<\(name)[^>]*>.*?</\(name)>",
                with: "",
                options: [.regularExpression, .caseInsensitive])
        }
    }

    /// The named entities that actually turn up in Italian university copy,
    /// plus numeric escapes in both decimal and hex.
    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // `&amp;` last among the named ones would still be wrong if done
        // first: `&amp;egrave;` must stay literal, so ampersand is decoded
        // only after every other entity has been consumed.
        result = decodeNumeric(result)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }

    private static func decodeNumeric(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else {
            return text
        }
        var result = text
        let matches = regex.matches(
            in: text, range: NSRange(text.startIndex..., in: text))
        // Back to front, so earlier ranges stay valid as the string shortens.
        for match in matches.reversed() {
            guard
                let full = Range(match.range, in: result),
                let flagRange = Range(match.range(at: 1), in: result),
                let digitsRange = Range(match.range(at: 2), in: result)
            else { continue }
            let isHex = !result[flagRange].isEmpty
            let digits = String(result[digitsRange])
            guard
                let value = UInt32(digits, radix: isHex ? 16 : 10),
                let scalar = Unicode.Scalar(value)
            else { continue }
            result.replaceSubrange(full, with: String(Character(scalar)))
        }
        return result
    }

    private static let named: [(String, String)] = [
        ("&nbsp;", " "), ("&#160;", " "),
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ("&agrave;", "à"), ("&egrave;", "è"), ("&eacute;", "é"),
        ("&igrave;", "ì"), ("&ograve;", "ò"), ("&ugrave;", "ù"),
        ("&Agrave;", "À"), ("&Egrave;", "È"), ("&Eacute;", "É"),
        ("&Igrave;", "Ì"), ("&Ograve;", "Ò"), ("&Ugrave;", "Ù"),
        ("&ccedil;", "ç"), ("&ntilde;", "ñ"), ("&uuml;", "ü"), ("&ouml;", "ö"),
        ("&auml;", "ä"), ("&szlig;", "ß"),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"),
        ("&euro;", "€"), ("&deg;", "°"), ("&bull;", "•"), ("&middot;", "·"),
        ("&laquo;", "«"), ("&raquo;", "»"), ("&times;", "×"), ("&reg;", "®"),
        ("&copy;", "©"), ("&trade;", "™"),
    ]

    /// A character that cannot appear in the source, standing in for a real
    /// line break until the source's own whitespace has been collapsed.
    private static let breakMark = "\u{0}"

    /// Collapses whitespace the way HTML does, then restores the real breaks.
    ///
    /// Every run of whitespace in a fragment — including the newlines it is
    /// wrapped with — is one space on screen. Only the marks inserted for
    /// block tags survive as newlines.
    private static func tidy(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(
            of: " *\(breakMark) *", with: breakMark, options: .regularExpression)
        // Three or more breaks is never meaningful; two reads as a paragraph.
        result = result.replacingOccurrences(
            of: "\(breakMark){3,}", with: breakMark + breakMark,
            options: .regularExpression)
        result = result.replacingOccurrences(of: breakMark, with: "\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

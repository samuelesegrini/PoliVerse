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
        var text = markBlocks(stripNonContent(html))

        // Then every remaining tag.
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)

        // Entities last, on purpose: an encoded `&lt;b&gt;` is text the author
        // wrote, not markup, and decoding before stripping would turn it into
        // a tag and delete it.
        text = decodeEntities(text)

        return tidy(text)
    }

    /// Script and style carry no reading content, and their bodies are not
    /// markup — dropping tags alone would leave CSS on screen.
    private static func stripNonContent(_ html: String) -> String {
        removeElements(named: ["script", "style", "head"], from: html)
    }

    /// Replaces block-level tags with break marks, leaving inline tags alone.
    private static func markBlocks(_ html: String) -> String {
        var text = html

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
        // `</li>` deliberately contributes nothing: the opening `<li>` above
        // already starts each item's line, and marking both would put a blank
        // line between every bullet.
        text = text.replacingOccurrences(
            of: "</li>", with: "", options: [.regularExpression, .caseInsensitive])
        // The list as a whole ends a block, like a paragraph.
        text = text.replacingOccurrences(
            of: "</ul>|</ol>",
            with: "\(Self.breakMark)\(Self.breakMark)",
            options: [.regularExpression, .caseInsensitive])

        return text
    }

    // MARK: - Rich text

    /// The inline formatting these fragments actually use.
    private struct Style: Equatable {
        var bold = false
        var italic = false
        var link: URL?
    }

    /// Renders the fragment as styled text: bold, italic, headings and
    /// tappable links.
    ///
    /// Still not `NSAttributedString`'s HTML importer — that one is
    /// WebKit-backed and main-actor bound. This is a plain scan over the
    /// string, so it is `nonisolated`, cheap, and cannot block a frame.
    ///
    /// Emphasis is expressed as `inlinePresentationIntent` rather than an
    /// explicit `Font`. SwiftUI honours it and, crucially, the text keeps
    /// whatever font the view gives it — so it still scales with Dynamic Type
    /// instead of being pinned to a size chosen here.
    static func attributed(_ html: String) -> AttributedString {
        let source = markBlocks(stripNonContent(html))
        var builder = Builder()
        var style = Style()
        var buffer = ""
        var index = source.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            builder.add(decodeEntities(buffer), style: style)
            buffer = ""
        }

        while index < source.endIndex {
            guard source[index] == "<",
                  let close = source[index...].firstIndex(of: ">")
            else {
                buffer.append(source[index])
                index = source.index(after: index)
                continue
            }

            flush()
            apply(tag: String(source[source.index(after: index)..<close]), to: &style)
            index = source.index(after: close)
        }
        flush()

        return builder.finish()
    }

    /// Updates the running style for one tag. Unknown tags are ignored, which
    /// is what makes an unexpected `<span class=…>` harmless.
    private static func apply(tag: String, to style: inout Style) {
        var body = tag.trimmingCharacters(in: .whitespaces)
        let isClosing = body.hasPrefix("/")
        if isClosing { body.removeFirst() }
        let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()

        switch name {
        case "b", "strong": style.bold = !isClosing
        case "i", "em": style.italic = !isClosing
        case "h1", "h2", "h3", "h4", "h5", "h6": style.bold = !isClosing
        case "a": style.link = isClosing ? nil : href(in: body)
        default: break
        }
    }

    /// Pulls the URL out of an anchor, quoted or not.
    ///
    /// Relative hrefs are dropped rather than guessed at: there is no base URL
    /// to resolve them against, and a link that silently goes nowhere is worse
    /// than text that is plainly not a link.
    private static func href(in tag: String) -> URL? {
        guard
            let match = tag.range(
                of: "href\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
                options: [.regularExpression, .caseInsensitive])
        else { return nil }

        var value = String(tag[match])
        guard let equals = value.firstIndex(of: "=") else { return nil }
        value = String(value[value.index(after: equals)...])
            .trimmingCharacters(in: .whitespaces)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        let decoded = decodeEntities(value)
        guard let url = URL(string: decoded), url.scheme != nil else { return nil }
        return url
    }

    /// Assembles the runs, applying HTML's whitespace rules as it goes.
    ///
    /// Collapsing afterwards is not an option once the string carries
    /// attributes — the runs would have to be walked and re-spliced. Doing it
    /// during the build keeps it to one pass and one rule.
    private struct Builder {
        private var result = AttributedString()
        private var pendingBreaks = 0
        /// Starts true so leading whitespace is dropped rather than indenting
        /// the first line.
        private var lastWasSpace = true
        private var isEmpty = true

        mutating func add(_ raw: String, style: Style) {
            // Break marks inside the text are the block boundaries recorded
            // earlier; everything between them is one run of inline content.
            let parts = raw.components(separatedBy: HTMLText.breakMark)
            for (offset, part) in parts.enumerated() {
                if offset > 0, !isEmpty {
                    // Accumulated, so the two marks a `</p>` leaves become a
                    // blank line while a single `<br>` stays one newline.
                    pendingBreaks = min(2, pendingBreaks + 1)
                    lastWasSpace = true
                }
                append(part, style: style)
            }
        }

        private mutating func append(_ raw: String, style: Style) {
            var text = raw.replacingOccurrences(
                of: "\\s+", with: " ", options: .regularExpression)
            if lastWasSpace, text.hasPrefix(" ") { text.removeFirst() }
            guard !text.isEmpty else { return }

            if pendingBreaks > 0 {
                result.append(AttributedString(String(repeating: "\n", count: pendingBreaks)))
                pendingBreaks = 0
            }

            var piece = AttributedString(text)
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link = style.link { piece.link = link }
            result.append(piece)

            lastWasSpace = text.hasSuffix(" ")
            isEmpty = false
        }

        /// Trailing breaks are simply never flushed; a trailing space can
        /// survive the last run, so drop it here.
        mutating func finish() -> AttributedString {
            while let last = result.characters.indices.last,
                  result.characters[last] == " " {
                result.removeSubrange(last..<result.endIndex)
            }
            return result
        }
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

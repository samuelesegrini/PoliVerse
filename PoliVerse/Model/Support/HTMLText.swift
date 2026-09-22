import Foundation

/// Renders the HTML fragments these endpoints send as readable text.
///
/// The news feed and the notice service both return their bodies as HTML
/// fragments. ``plain(_:)`` produces plain text with block structure kept as line
/// breaks; ``attributed(_:)`` produces an `AttributedString` with bold, italic and
/// tappable links.
///
/// Neither goes through `NSAttributedString`'s HTML importer, which is
/// WebKit-backed and main-actor bound. Both are plain scans over the string, so
/// they are `nonisolated` and cannot block a frame.
///
/// Emphasis is expressed as `inlinePresentationIntent` rather than an explicit
/// `Font`, so the text keeps whatever font the view gives it and still scales with
/// Dynamic Type.
nonisolated enum HTMLText {
    /// A fragment as plain text, with block structure preserved as line breaks.
    ///
    /// Script, style and head elements are dropped whole, block tags become breaks,
    /// remaining tags are stripped, and entities are decoded last — so an encoded
    /// `&lt;b&gt;` stays literal text rather than becoming a tag and being deleted.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The text. A paragraph or heading ends with a blank line, a `<br>`
    ///   with a single newline, and list items are bulleted.
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

    /// Removes `script`, `style` and `head` elements with their contents.
    ///
    /// Their bodies are not markup, so stripping tags alone would leave CSS on screen.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The fragment without those elements.
    private static func stripNonContent(_ html: String) -> String {
        removeElements(named: ["script", "style", "head"], from: html)
    }

    /// Replaces block-level tags with break marks, leaving inline tags in place.
    ///
    /// Breaks are recorded as ``breakMark`` rather than as newlines so that the next
    /// step can tell them from the newlines in the source, which HTML treats as spaces.
    /// A paragraph, heading, blockquote or list close leaves two marks; a `<br>` or row
    /// close leaves one; a list item opens a line and a bullet.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The fragment with block boundaries marked.
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

    /// The inline formatting these fragments use.
    private struct Style: Equatable {
        /// Whether the run is strongly emphasised.
        var bold = false
        /// Whether the run is emphasised.
        var italic = false
        /// The link the run sits inside, if any.
        var link: URL?
    }

    /// A fragment as styled text: bold, italic, headings and tappable links.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The attributed text, with whitespace collapsed to HTML's rules and
    ///   block boundaries rendered as line breaks.
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

    /// Updates the running style for one tag.
    ///
    /// `b` and `strong` and the six heading levels set bold, `i` and `em` set italic,
    /// and `a` sets the link. Unknown tags are ignored, which is what makes an
    /// unexpected `<span class=…>` harmless.
    ///
    /// - Parameters:
    ///   - tag: The tag's body, without its angle brackets.
    ///   - style: The running style to update.
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

    /// The URL of an anchor tag, quoted with either quote character or unquoted.
    ///
    /// Relative links are dropped rather than guessed at: there is no base URL to
    /// resolve them against, and a link that goes nowhere is worse than plain text.
    ///
    /// - Parameter tag: The anchor's body.
    /// - Returns: The absolute URL, or `nil`.
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

    /// Assembles the runs of an ``AttributedString``, applying HTML's whitespace rules
    /// as it goes.
    ///
    /// Collapsing whitespace afterwards would mean walking and re-splicing attributed
    /// runs; doing it during the build keeps it to one pass.
    private struct Builder {
        /// What has been built so far.
        private var result = AttributedString()
        /// Block breaks recorded but not yet written, capped at two. Never flushed at the
        /// end, so the result has no trailing newlines.
        private var pendingBreaks = 0
        /// Whether the last character written was a space. Starts `true`, so leading
        /// whitespace is dropped rather than indenting the first line.
        private var lastWasSpace = true
        /// Whether anything has been written. Suppresses breaks before the first run.
        private var isEmpty = true

        /// Appends one piece of text, splitting it on the block marks recorded earlier and
        /// decoding its entities.
        ///
        /// - Parameters:
        ///   - raw: The text, which may contain ``HTMLText/breakMark``.
        ///   - style: The formatting in force.
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

        /// Appends one run, collapsing its whitespace and applying the style.
        ///
        /// - Parameters:
        ///   - raw: The text of one run, without block marks.
        ///   - style: The formatting to apply.
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

        /// The assembled text, with any trailing spaces removed.
        ///
        /// - Returns: The finished string.
        mutating func finish() -> AttributedString {
            while let last = result.characters.indices.last,
                  result.characters[last] == " " {
                result.removeSubrange(last..<result.endIndex)
            }
            return result
        }
    }

    /// Whether a string looks like it carries tags or entities.
    ///
    /// - Parameter string: The string to test.
    /// - Returns: `true` when a tag or an entity is present.
    static func containsMarkup(_ string: String) -> Bool {
        string.range(of: "<[^>]+>|&[#a-zA-Z][a-zA-Z0-9]{1,9};",
                     options: .regularExpression) != nil
    }

    /// Strips markup only when there is some, so a plain string is returned untouched.
    ///
    /// - Parameter string: The string to clean.
    /// - Returns: The plain text, or the input unchanged.
    static func plainIfNeeded(_ string: String) -> String {
        containsMarkup(string) ? plain(string) : string
    }

    /// Removes named elements together with their contents.
    ///
    /// - Parameters:
    ///   - names: The element names to remove.
    ///   - html: The fragment.
    /// - Returns: The fragment without those elements.
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

    /// Decodes HTML entities: the named set in ``named``, then numeric escapes, then
    /// `&amp;` last — so `&amp;egrave;` stays literal instead of becoming `è`.
    ///
    /// - Parameter text: The text to decode.
    /// - Returns: The decoded text.
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

    /// Decodes `&#nnn;` and `&#xhh;` escapes.
    ///
    /// Replacements are applied back to front so earlier ranges stay valid. An escape
    /// that names no scalar is left as written.
    ///
    /// - Parameter text: The text to decode.
    /// - Returns: The decoded text.
    private static func decodeNumeric(_ text: String) -> String {
        guard let regex = RegexCache.regex("&#(x?)([0-9a-fA-F]+);") else {
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

    /// The named entities that appear in Italian university copy, with their
    /// replacements. Applied in order, with `&amp;` handled separately and last.
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

    /// Stands in for a real line break until the source's own whitespace has been
    /// collapsed. A character that cannot appear in the source.
    private static let breakMark = "\u{0}"

    /// Collapses whitespace the way HTML does, then turns the surviving marks into
    /// newlines.
    ///
    /// Every run of whitespace becomes one space; runs of three or more block marks
    /// become two, which reads as a paragraph break.
    ///
    /// - Parameter text: The marked text.
    /// - Returns: The text, trimmed.
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

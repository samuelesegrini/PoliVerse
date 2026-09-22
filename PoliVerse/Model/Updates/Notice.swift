import Foundation

/// A message from the Politecnico — the bell in the official app.
///
/// `GET {app}/v1/notifications` lists them, and
/// `GET {app}/v1/notifications/{id_notice}` carries the full text of one.
///
/// - Important: the response body has not been captured from a real account. Only the
///   path parameter's name is known, from the official client, so every field is read
///   by trying a list of plausible names — see ``init(fields:index:)`` — and
///   ``NoticeSource`` logs the payload's shape so the guesses can be replaced with
///   fact after a single run.
nonisolated struct Notice: Identifiable, Sendable, Hashable, Codable {
    /// The notice's identity, which the detail call takes. Falls back to the row's
    /// position when the payload carries no identifier at all.
    let id: String
    /// The notice's title, falling back to a generic word.
    let title: String
    /// The summary or full text as plain text, for rows. The detail endpoint is what
    /// carries the whole thing.
    let body: String?
    /// The same content with its markup intact, when it arrived as HTML, so the detail
    /// view can render bold and links rather than flat text.
    var bodyHTML: String?
    /// When the notice was sent, where the payload says.
    let date: Date?
    /// Which service or channel it came from, where the payload says.
    let category: String?
    /// Upstream's own read flag. `nil` when it sends none, in which case read state is
    /// tracked on the device.
    let serverRead: Bool?
    /// Whether the notice counts as read: the server's flag where there is one, and what
    /// this device remembers otherwise. Resolved by ``NoticeSource/adjust(_:)``.
    var isRead: Bool = false
    /// A link out to the web, where the payload carries one.
    let link: URL?
}

/// Reading a notice out of a payload whose field names are not known.
nonisolated extension Notice {
    /// Builds a notice from a payload, trying a list of candidate key spellings for each
    /// field.
    ///
    /// Everything but the identity and the title degrades to `nil` rather than dropping
    /// the row: a notice missing its date is still worth reading.
    ///
    /// - Parameters:
    ///   - fields: One notice's fields.
    ///   - index: The row's position, which keeps rows distinct when the payload carries
    ///     no identifier.
    /// - Returns: `nil` only when there is neither an identity nor a title, which is a row
    ///   that can be neither addressed nor displayed.
    init?(fields: [String: JSONValue], index: Int) {
        let rawID = fields.firstValue([
            "id_notice", "idNotice", "id", "notice_id", "id_notifica",
            "id_messaggio", "messageId", "uuid", "guid",
        ])?.stringValue

        let title = fields.firstValue([
            "title", "titolo", "oggetto", "subject", "descrizione",
            "description", "header", "testata",
        ]).flatMap(Notice.text(from:))

        let rawBody = fields.firstValue([
            "body", "testo", "text", "messaggio", "message", "contenuto",
            "content", "descrizione_estesa", "abstract", "summary", "html",
        ]).flatMap(Notice.rawText(from:))
        let body = rawBody.map(HTMLText.plainIfNeeded)?.nonEmpty

        // Neither addressable nor displayable: nothing to show and nothing to
        // fetch. Anything less complete than that is still worth a row.
        guard rawID != nil || title != nil else { return nil }

        self.init(
            // The index keeps rows distinct when the payload carries no id at
            // all, so SwiftUI does not collapse them — the same duplicate-ID
            // problem the WeBeep course list hit.
            id: rawID ?? "notice-\(index)",
            title: title ?? "Comunicazione",
            body: body,
            bodyHTML: Notice.markup(rawBody),
            date: fields.firstValue([
                "date", "data", "data_inserimento", "dataInserimento",
                "data_invio", "dataInvio", "timestamp", "created_at",
                "createdAt", "data_pubblicazione", "publish_date", "sent_at",
            ]).flatMap(Notice.date(from:)),
            category: fields.firstValue([
                "category", "categoria", "tipo", "type", "tipologia",
                "channel", "canale", "servizio", "service",
            ]).flatMap(Notice.text(from:)),
            serverRead: Notice.readFlag(in: fields),
            link: fields.firstValue([
                "link", "url", "href", "target_url", "deeplink", "link_url",
            ])?.stringValue.flatMap(URL.init(string:))
        )
    }

    /// A string field as plain text, accepting either a bare string or an `{it, en}` pair.
    ///
    /// Markup is stripped here rather than at display time, so every view shows text
    /// rather than source.
    ///
    /// - Parameter value: The decoded field.
    /// - Returns: The text, or `nil` when it is absent or empty.
    static func text(from value: JSONValue) -> String? {
        rawText(from: value).map(HTMLText.plainIfNeeded)?.nonEmpty
    }

    /// The same reading with markup left in place, for the fields a detail view renders
    /// richly.
    ///
    /// - Parameter value: The decoded field.
    /// - Returns: The text as written, or `nil` when it is absent or empty.
    static func rawText(from value: JSONValue) -> String? {
        if let fields = value.objectValue {
            let localised = fields.firstValue(["it", "ita", "italian"])?.stringValue
                ?? fields.firstValue(["en", "eng", "english"])?.stringValue
            return localised?.nonEmpty
        }
        return value.stringValue?.nonEmpty
    }

    /// The original markup, but only when there is some — a plain string is already its own
    /// best rendering, and storing it twice helps nobody.
    ///
    /// - Parameter raw: The text as written.
    /// - Returns: The text when it carries markup, and `nil` otherwise.
    static func markup(_ raw: String?) -> String? {
        guard let raw, HTMLText.containsMarkup(raw) else { return nil }
        return raw
    }

    /// ISO 8601 without fractional seconds. Shared, which `ISO8601DateFormatter` documents
    /// as safe.
    private nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()
    /// ISO 8601 with fractional seconds.
    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// A timestamp in any of the forms these services use.
    ///
    /// A number is epoch seconds or milliseconds, told apart by magnitude. A string is
    /// tried as ISO 8601, then as ISO 8601 with fractional seconds, then as Rome wall clock
    /// with a `T` separator, and finally as Rome wall clock with a space — which is how the
    /// JAF services tend to write it.
    ///
    /// - Parameter value: The decoded field.
    /// - Returns: The date, or `nil` when no form matches.
    static func date(from value: JSONValue) -> Date? {
        if let number = value.doubleValue, number > 0 {
            // Seconds and milliseconds are told apart by magnitude: epoch
            // seconds stay below 10^11 until the year 5138, and epoch
            // milliseconds passed it in 1973.
            return number > 100_000_000_000
                ? Date(timeIntervalSince1970: number / 1000)
                : Date(timeIntervalSince1970: number)
        }
        guard let text = value.stringValue?.nonEmpty else { return nil }
        if let iso = isoPlain.date(from: text) { return iso }
        if let iso = isoFractional.date(from: text) { return iso }
        // Falls through to the agenda's reading: wall clock, Europe/Rome.
        if let wallClock = PoliMiDate.parse(text) { return wallClock }
        // The agenda separates date from time with `T`; JAF's own services
        // tend to use a space. Kept here rather than in ``PoliMiDate`` so a
        // guess made for an unconfirmed endpoint cannot alter the parsing of
        // the agenda and libretto, both of which are verified against a real
        // account.
        return Notice.spacedWallClock.date(from: text)
    }

    /// `yyyy-MM-dd HH:mm:ss` in Europe/Rome.
    ///
    /// Kept here rather than in ``PoliMiDate`` so that a guess made for an unconfirmed
    /// endpoint cannot alter the parsing of the agenda and the libretto, both of which are
    /// verified against a real account.
    static let spacedWallClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Upstream's read flag, however it is expressed.
    ///
    /// A read timestamp means read and an empty one unread; a negative flag such as
    /// `unread` is inverted rather than reported as everything being unread.
    ///
    /// - Parameter fields: One notice's fields.
    /// - Returns: Whether the notice is read, or `nil` when the payload says nothing.
    static func readFlag(in fields: [String: JSONValue]) -> Bool? {
        if let read = fields.firstValue([
            "read", "letto", "is_read", "isRead", "visualizzato", "seen",
            "data_lettura", "readAt",
        ]) {
            // A read *timestamp* means read; an empty one means unread.
            if case .string(let text) = read { return !text.isEmpty }
            return read.boolValue ?? (read.intValue.map { $0 != 0 })
        }
        if let unread = fields.firstValue([
            "unread", "non_letto", "da_leggere", "is_new", "nuovo", "new",
        ])?.boolValue {
            return !unread
        }
        return nil
    }
}

/// The list payload, which may be a bare array or an array behind a key.
///
/// Both conventions are in use across the services this app talks to.
nonisolated struct NoticesResponse: Decodable, Sendable {
    /// The notices read out of the payload. Empty when none could be.
    let notices: [Notice]
    /// The payload as it arrived, so its shape can be logged without parsing it again.
    let raw: JSONValue

    /// Decodes the payload into ``JSONValue`` and extracts the notices from it.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not JSON at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        notices = NoticesResponse.extract(from: value)
    }

    /// Reads notices out of a decoded payload, whatever it is wrapped in.
    ///
    /// An array is read directly. An object is followed into the first named key holding an
    /// array, then into any array-valued member — the name being exactly what is unknown —
    /// and finally read as a single notice.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The notices, or an empty array when none can be read.
    static func extract(from value: JSONValue) -> [Notice] {
        if let items = value.arrayValue {
            return items.enumerated().compactMap { index, item in
                item.objectValue.flatMap { Notice(fields: $0, index: index) }
            }
        }
        guard let fields = value.objectValue else { return [] }
        // A wrapper: take the first array-valued key rather than insisting on
        // a name, since the name is exactly what is unknown.
        let candidates = ["notifications", "notifiche", "notices", "avvisi",
                          "data", "items", "results", "content", "list",
                          "elementi", "NOTIFICATIONS"]
        if let named = fields.firstValue(candidates), named.arrayValue != nil {
            return extract(from: named)
        }
        if let anyArray = fields.values.first(where: { $0.arrayValue != nil }) {
            return extract(from: anyArray)
        }
        // A single object: one notification, not a list.
        return Notice(fields: fields, index: 0).map { [$0] } ?? []
    }
}

/// Small string conveniences these payloads need.
nonisolated extension String {
    /// The string trimmed, or `nil` when nothing is left.
    ///
    /// An empty string is how these backends spell absent, and an empty title is worse than
    /// a fallback one.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The first letter upper-cased and the rest left alone.
    ///
    /// `capitalized` capitalises every word, which is right for a title and wrong for a
    /// phrase.
    var sentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

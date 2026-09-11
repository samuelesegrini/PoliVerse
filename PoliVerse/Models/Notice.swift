import Foundation

/// A message from the Politecnico — the bell in the official app.
///
/// `GET {app}/v1/notifications`, with `GET {app}/v1/notifications/{id_notice}`
/// for the full text of one. The path parameter's name is the only thing about
/// this endpoint that is documented: it appears as `id_notice` in the official
/// bundle's own client, which is why `id_notice` heads the list of candidate
/// keys below.
///
/// - Important: the response body has **never been captured from a real
///   account**. Everything except that one parameter name is a guess, so this
///   reads fields by trying a list of plausible names rather than binding to
///   one, and ``NoticeService`` logs the payload's shape so the guess can be
///   replaced with fact after a single run.
nonisolated struct Notice: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    /// The summary or full text, where the list carries one. The detail
    /// endpoint is what has the whole thing. Plain text, for rows.
    let body: String?
    /// The same content with its markup intact, when it arrived as HTML, so
    /// the detail view can render bold and links rather than flat text.
    var bodyHTML: String?
    let date: Date?
    let category: String?
    /// Upstream's own read flag, when it sends one. Nil means it does not,
    /// and read state is tracked on the device instead.
    let serverRead: Bool?
    /// Resolved by ``NoticeService``: the server's flag when there is one,
    /// otherwise what this device remembers.
    var isRead: Bool = false
    /// Whether a link out to the web exists for this notice.
    let link: URL?
}

nonisolated extension Notice {
    /// Builds a notice from a payload whose field names are not known.
    ///
    /// Returns nil only when there is no usable identity **and** no title —
    /// a row that can be neither addressed nor displayed. Everything else
    /// degrades to nil rather than dropping the row: a notification missing
    /// its date is still worth reading.
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

    /// Reads a string that may be a plain string or an `{it, en}` pair — the
    /// agenda sends every label the second way, so this endpoint may too.
    ///
    /// Markup is stripped here rather than at display time. These fields
    /// arrive as HTML fragments — the news description reached the screen as
    /// literal `<p>` and `&egrave;` — and doing it once on the way in means
    /// every view, row and detail alike, shows text rather than source.
    static func text(from value: JSONValue) -> String? {
        rawText(from: value).map(HTMLText.plainIfNeeded)?.nonEmpty
    }

    /// The same reading, with markup left in place.
    ///
    /// Kept for the fields a detail view renders richly — the plain form is
    /// what rows and titles want, the original is what carries the bold and
    /// the links.
    static func rawText(from value: JSONValue) -> String? {
        if let fields = value.objectValue {
            let localised = fields.firstValue(["it", "ita", "italian"])?.stringValue
                ?? fields.firstValue(["en", "eng", "english"])?.stringValue
            return localised?.nonEmpty
        }
        return value.stringValue?.nonEmpty
    }

    /// The original markup, but only when there is some — a plain string is
    /// already its own best rendering and storing it twice helps nobody.
    static func markup(_ raw: String?) -> String? {
        guard let raw, HTMLText.containsMarkup(raw) else { return nil }
        return raw
    }

    /// Reads a timestamp in any of the forms PoliMi's services actually use.
    ///
    /// All four appear across endpoints already in this app: the libretto
    /// sends epoch **milliseconds**, the agenda sends timezone-less wall clock
    /// in Europe/Rome, and other services send ISO 8601. Guessing one would be
    /// a coin flip, so try them in order of how unambiguous they are.
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
        if let iso = ISO8601DateFormatter().date(from: text) { return iso }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let iso = fractional.date(from: text) { return iso }
        // Falls through to the agenda's reading: wall clock, Europe/Rome.
        if let wallClock = PoliMiDate.parse(text) { return wallClock }
        // The agenda separates date from time with `T`; JAF's own services
        // tend to use a space. Kept here rather than in ``PoliMiDate`` so a
        // guess made for an unconfirmed endpoint cannot alter the parsing of
        // the agenda and libretto, both of which are verified against a real
        // account.
        return Notice.spacedWallClock.date(from: text)
    }

    /// `yyyy-MM-dd HH:mm:ss`, read as Europe/Rome like every other
    /// timezone-less timestamp these services send.
    static let spacedWallClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Upstream may express "read" either way round, so look for both and
    /// invert the negative one rather than reporting everything unread.
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
/// Both conventions are in use across the services this app already talks to:
/// `/v1/insegn` wraps its array in `INSEGN`, the agenda returns a bare array.
nonisolated struct NoticesResponse: Decodable, Sendable {
    let notices: [Notice]
    /// Kept so the service can log the payload's shape without re-parsing it.
    let raw: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        notices = NoticesResponse.extract(from: value)
    }

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

nonisolated extension String {
    /// Empty strings are how these backends spell "absent", and an empty
    /// title is worse than a fallback one.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

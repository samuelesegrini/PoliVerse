import Foundation

/// A news item from the Politecnico.
///
/// `GET {agenda}/v1/persona/news`, with `start_date` and `end_date`. The response shape
/// is verified against a real account:
///
/// ```json
/// {"news_id": 123, "news_source_id": 4,
///  "title": {"it": "…", "en": "…"}, "text": {"it": "…", "en": "…"},
///  "publication_start": "…", "publication_end": "…",
///  "event_start": "…", "event_end": "…",
///  "show_agenda": true, "tags": [{…}]}
/// ```
///
/// - Important: there are two distinct date pairs. `publication_*` is when the item is
///   on the board; `event_*` is when the thing it announces happens. Confusing them
///   would retire a notice about next month's seminar the moment it was published.
nonisolated struct NewsItem: Identifiable, Sendable, Hashable, Codable {
    /// The item's identity. Falls back to the row's position when the payload carries no
    /// identifier.
    let id: String
    /// The item's title, falling back to a generic word.
    let title: String
    /// The body as plain text, for rows.
    let summary: String?
    /// The same content with its markup intact, when it arrived as HTML, so the detail view
    /// can render bold and links.
    var summaryHTML: String?
    /// When the item went on the board — `publication_start`.
    let published: Date?
    /// When it stops being posted — `publication_end`.
    let expires: Date?
    /// When the thing being announced happens, which is often the date worth showing.
    var eventStart: Date?
    /// When it finishes, for something spanning several days.
    var eventEnd: Date?

    /// The date to show: the event's where there is one, and the publication date
    /// otherwise.
    ///
    /// A seminar's date is what a reader wants; the day the notice went up matters only
    /// when it announces nothing scheduled.
    var displayDate: Date? { eventStart ?? published }
    /// Which channel or tag the item came from, where the payload says.
    let category: String?
    /// A link out to the web, where the payload carries one.
    let link: URL?
    /// A picture for the item, where the payload carries one.
    let imageURL: URL?

    /// Whether the item is still posted.
    ///
    /// Only an explicit ``expires`` can retire an item: treating a missing one as expired
    /// would empty the screen the moment a field name turned out to be wrong.
    ///
    /// - Parameter now: The moment to judge at.
    /// - Returns: `true` when the item should still be shown.
    func isCurrent(now: Date = .now) -> Bool {
        guard let expires else { return true }
        return expires >= now
    }
}

/// Reading an item out of the payload, and formatting what it says.
nonisolated extension NewsItem {
    /// Builds an item from a payload, trying a list of candidate key spellings for each
    /// field.
    ///
    /// The verified keys lead each list; the rest are kept as fallbacks for the sibling
    /// endpoints that share this reader.
    ///
    /// - Parameters:
    ///   - fields: One item's fields.
    ///   - index: The row's position, which keeps rows distinct when the payload carries no
    ///     identifier.
    /// - Returns: `nil` only when there is neither an identity nor a title.
    init?(fields: [String: JSONValue], index: Int) {
        let rawID = fields.firstValue([
            "news_id", "event_id", "id", "id_news", "newsId", "uuid", "guid",
        ])?.stringValue

        let title = fields.firstValue([
            "title", "titolo", "headline", "oggetto", "nome", "name",
        ]).flatMap(Notice.text(from:))

        guard rawID != nil || title != nil else { return nil }

        let rawSummary = fields.firstValue([
            "description", "descrizione", "summary", "abstract",
            "sommario", "testo", "body", "content", "contenuto", "text",
        ]).flatMap(Notice.rawText(from:))

        self.init(
            id: rawID ?? "news-\(index)",
            title: title ?? "Notizia",
            summary: rawSummary.map(HTMLText.plainIfNeeded)?.nonEmpty,
            summaryHTML: Notice.markup(rawSummary),
            // `publication_start` is the real key; the rest are kept as
            // fallbacks for the sibling endpoints that share this reader.
            published: fields.firstValue([
                "publication_start", "date_start", "data_inizio", "date",
                "data", "published_at", "data_pubblicazione", "created_at",
            ]).flatMap(Notice.date(from:)),
            expires: fields.firstValue([
                "publication_end", "date_end", "data_fine", "expires_at",
                "data_scadenza", "valid_until",
            ]).flatMap(Notice.date(from:)),
            eventStart: fields.firstValue([
                "event_start", "data_evento", "start_date",
            ]).flatMap(Notice.date(from:)),
            eventEnd: fields.firstValue([
                "event_end", "end_date",
            ]).flatMap(Notice.date(from:)),
            category: NewsItem.category(in: fields),
            link: fields.firstValue([
                "link", "url", "href", "link_url", "target_url", "permalink",
                "read_more", "approfondimento",
            ])?.stringValue.flatMap(URL.init(string:)),
            imageURL: fields.firstValue([
                "image", "image_url", "immagine", "cover", "thumbnail",
                "picture", "media_url",
            ]).flatMap(NewsItem.url(from:))
        )
    }

    /// A date, or a range of dates, as one phrase.
    ///
    /// - Parameters:
    ///   - start: When the thing begins.
    ///   - end: When it finishes, or `nil`.
    /// - Returns: The start alone when there is no end or it falls on the same Rome day,
    ///   and both joined by a dash otherwise.
    static func span(from start: Date, to end: Date?) -> String {
        let startText = start.formatted(date: .long, time: .omitted)
        guard let end, !PoliMiDate.romeCalendar.isDate(end, inSameDayAs: start) else {
            return startText
        }
        return "\(startText) – \(end.formatted(date: .long, time: .omitted))"
    }

    /// The item's category, however the payload expresses it.
    ///
    /// The agenda writes it as a flat string, as a nested object, or as the first entry of a
    /// `tags` array, so all three are unwrapped.
    ///
    /// - Parameter fields: One item's fields.
    /// - Returns: The category, or `nil` when the payload says nothing.
    static func category(in fields: [String: JSONValue]) -> String? {
        if let direct = fields.firstValue([
            "category", "categoria", "tipo", "type", "tipologia", "channel",
        ]) {
            if let text = Notice.text(from: direct) { return text }
            if let nested = direct.objectValue,
               let name = nested.firstValue(["type_dn", "denomination", "descrizione", "name"]) {
                return Notice.text(from: name)
            }
        }
        if let tags = fields.firstValue(["tags", "etichette", "labels"])?.arrayValue,
           let first = tags.first?.objectValue,
           let name = first.firstValue(["denomination", "nome", "name", "descrizione"]) {
            return Notice.text(from: name)
        }
        return nil
    }

    /// A URL field, which may be a bare string or an object wrapping one.
    ///
    /// - Parameter value: The decoded field.
    /// - Returns: The URL, or `nil` when none can be read.
    static func url(from value: JSONValue) -> URL? {
        if let string = value.stringValue?.nonEmpty {
            return URL(string: string)
        }
        guard let fields = value.objectValue else { return nil }
        return fields.firstValue(["url", "href", "src", "path"])?
            .stringValue.flatMap(URL.init(string:))
    }
}

/// The news payload: a bare array, or an array behind a key.
nonisolated struct NewsResponse: Decodable, Sendable {
    /// The items read out of the payload. Empty when none could be.
    let items: [NewsItem]
    /// The payload as it arrived, so its shape can be logged without parsing it again.
    let raw: JSONValue

    /// Decodes the payload into ``JSONValue`` and extracts the items from it.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not JSON at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        items = NewsResponse.extract(from: value)
    }

    /// Reads items out of a decoded payload, whatever it is wrapped in, by the same rules as
    /// ``NoticesResponse/extract(from:)``.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The items, or an empty array when none can be read.
    static func extract(from value: JSONValue) -> [NewsItem] {
        if let items = value.arrayValue {
            return items.enumerated().compactMap { index, item in
                item.objectValue.flatMap { NewsItem(fields: $0, index: index) }
            }
        }
        guard let fields = value.objectValue else { return [] }
        let candidates = ["news", "notizie", "items", "results", "data",
                          "content", "list", "elementi", "NEWS"]
        if let named = fields.firstValue(candidates), named.arrayValue != nil {
            return extract(from: named)
        }
        if let anyArray = fields.values.first(where: { $0.arrayValue != nil }) {
            return extract(from: anyArray)
        }
        return NewsItem(fields: fields, index: 0).map { [$0] } ?? []
    }
}

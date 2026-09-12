import Foundation

/// A news item from the Politecnico.
///
/// `GET {agenda}/v1/persona/news`, with `start_date` / `end_date` and the
/// optional `show_in_agenda` and `filter_by_interests` flags. The official app
/// asks for today through a year ahead.
///
/// The response shape is now VERIFIED against a real account (2026-09-11):
///
/// ```json
/// {"news_id": 123, "news_source_id": 4,
///  "title": {"it": "…", "en": "…"}, "text": {"it": "…", "en": "…"},
///  "publication_start": "…", "publication_end": "…",
///  "event_start": "…", "event_end": "…",
///  "show_agenda": true, "tags": [{…}]}
/// ```
///
/// Two distinct date pairs, which the first cut of this file missed entirely
/// by guessing `date_start` from the agenda's events: `publication_*` is when
/// the item is on the board, `event_*` is when the thing it announces
/// happens. Getting them confused would retire a notice about next month's
/// seminar the moment it was published.
nonisolated struct NewsItem: Identifiable, Sendable, Hashable, Codable {
    let id: String
    let title: String
    /// Plain text, for rows.
    let summary: String?
    /// The same content with its markup intact, when it arrived as HTML, so
    /// the detail view can render bold and links.
    var summaryHTML: String?
    let published: Date?
    /// When the item stops being posted — `publication_end`.
    let expires: Date?
    /// When the thing being announced happens, which is a different date from
    /// when the announcement went up and is often the one worth showing.
    var eventStart: Date?
    var eventEnd: Date?

    /// The date to show: the event where there is one, otherwise publication.
    /// A seminar's date is what a reader wants; the day the notice went up is
    /// only interesting when it announces nothing scheduled.
    var displayDate: Date? { eventStart ?? published }
    let category: String?
    let link: URL?
    let imageURL: URL?

    /// Whether this item is still current, as of `now`.
    ///
    /// Only an *explicit* end date can retire an item. Treating a missing one
    /// as expired would empty the screen the moment the guess about field
    /// names is wrong, which is precisely the failure mode to avoid here.
    func isCurrent(now: Date = .now) -> Bool {
        guard let expires else { return true }
        return expires >= now
    }
}

nonisolated extension NewsItem {
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

    /// "10 marzo" or "10–12 marzo", skipping an end that adds nothing.
    static func span(from start: Date, to end: Date?) -> String {
        let startText = start.formatted(date: .long, time: .omitted)
        guard let end, !PoliMiDate.romeCalendar.isDate(end, inSameDayAs: start) else {
            return startText
        }
        return "\(startText) – \(end.formatted(date: .long, time: .omitted))"
    }

    /// The agenda expresses a category as a nested `{type_dn: {it, en}}` or as
    /// the first of a `tags` array, so unwrap both rather than only reading a
    /// flat string.
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

    /// An image may be a bare URL string or an object wrapping one.
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
    let items: [NewsItem]
    let raw: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        items = NewsResponse.extract(from: value)
    }

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

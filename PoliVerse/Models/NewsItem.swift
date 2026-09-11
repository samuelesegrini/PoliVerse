import Foundation

/// A news item from the Politecnico.
///
/// `GET {agenda}/v1/persona/news`, with `start_date` / `end_date` and the
/// optional `show_in_agenda` and `filter_by_interests` flags. The official app
/// asks for today through a year ahead.
///
/// The path and its query parameters are VERIFIED from the official bundle;
/// the **response body is not**. It sits on the agenda service beside
/// `/v1/matricola/{m}/events`, whose shape *is* known, so the field names
/// there — `title: {it, en}`, `date_start`, `event_id` — head the candidate
/// lists as the most likely answer rather than being assumed to be the answer.
nonisolated struct NewsItem: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let summary: String?
    let published: Date?
    /// Where the news runs out: news carries an end date on the agenda host,
    /// and something already over is not news.
    let expires: Date?
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

        self.init(
            id: rawID ?? "news-\(index)",
            title: title ?? "Notizia",
            summary: fields.firstValue([
                "description", "descrizione", "summary", "abstract",
                "sommario", "testo", "body", "content", "contenuto", "text",
            ]).flatMap(Notice.text(from:)),
            published: fields.firstValue([
                "date_start", "dateStart", "data_inizio", "date", "data",
                "published_at", "data_pubblicazione", "start_date",
                "created_at", "timestamp",
            ]).flatMap(Notice.date(from:)),
            expires: fields.firstValue([
                "date_end", "dateEnd", "data_fine", "end_date", "expires_at",
                "data_scadenza", "valid_until",
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

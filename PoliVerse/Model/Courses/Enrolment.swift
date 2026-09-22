import Foundation

/// One of the student's enrolments, as `GET {app}/v1/careers/list` lists it.
///
/// A person has a single person code and a matricola per enrolment — a finished
/// triennale and a starting magistrale are two careers and one human. Nearly every
/// endpoint is parameterised by matricola and the OAuth token is bound to one of
/// them, so a closed career's services refuse the token outright. Which career is
/// in use therefore decides whether the app works at all.
///
/// - Note: named `Career` but declared in `Enrolment.swift`, because `Career.swift`
///   holds the gradebook and the exam sittings.
nonisolated struct Career: Identifiable, Sendable, Hashable, Codable {
    /// ``matricola``.
    var id: String { matricola }
    /// The enrolment number this career is keyed by.
    let matricola: String
    /// The kind of degree, for example “Laurea Magistrale”, where the payload says.
    let kind: String?
    /// The enrolment's status, as upstream words it — “Attiva” or “Chiusa”.
    let status: String?

    /// Whether this enrolment is open, and so the one whose exam services will answer.
    ///
    /// Read from ``status``, matching the Italian and English wordings upstream uses.
    /// `false` when no status is recorded.
    var isActive: Bool {
        guard let status = status?.lowercased() else { return false }
        return status.contains("attiv") || status.contains("active")
            || status.contains("in corso")
    }

    /// Kind and status as one line, joined by a middle dot.
    var label: String {
        [kind, status].compactMap { $0 }.joined(separator: " · ")
    }

    /// The career to use when the student has not chosen one: the active one, else the
    /// first.
    ///
    /// - Parameter careers: The enrolments to choose from.
    /// - Returns: The preferred career. Never `nil` for a non-empty list, since leaving
    ///   it unset would send every request without a matricola.
    static func preferred(in careers: [Career]) -> Career? {
        careers.first(where: \.isActive) ?? careers.first
    }
}

/// The answer to `/v1/careers/list`, which may be a bare array or an array behind a
/// key.
///
/// Decoded through ``JSONValue`` and read by ``extract(from:)``, so an unexpected
/// field type in one row cannot fail the whole list.
nonisolated struct CareersResponse: Decodable, Sendable {
    /// The enrolments read out of the payload. Empty when none could be.
    let careers: [Career]
    /// The payload as it arrived, for diagnostics.
    let raw: JSONValue

    /// Decodes the payload into ``JSONValue`` and extracts the enrolments from it.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not JSON at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        careers = CareersResponse.extract(from: value)
    }

    /// Reads enrolments out of a decoded payload, whatever it is wrapped in.
    ///
    /// An array is read directly, each element needing only a non-empty matricola. An
    /// object is followed into the first of `carriere`, `careers`, `data`, `items`,
    /// `elenco` or `list` that holds an array, and failing that into any array-valued
    /// member.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The enrolments, or an empty array when none can be read.
    static func extract(from value: JSONValue) -> [Career] {
        if let items = value.arrayValue {
            return items.compactMap { item -> Career? in
                guard
                    let fields = item.objectValue,
                    let matricola = fields.firstValue([
                        "matricola", "codice_matricola", "id",
                    ])?.stringValue, !matricola.isEmpty
                else { return nil }

                return Career(
                    matricola: matricola,
                    kind: fields.firstValue([
                        "desc_tipo_carriera", "tipo_carriera", "descrizione",
                        "corso", "desc_corso",
                    ]).flatMap(Notice.text(from:)),
                    status: fields.firstValue([
                        "desc_stato_carriera", "stato_carriera", "stato",
                    ]).flatMap(Notice.text(from:)))
            }
        }
        guard let fields = value.objectValue else { return [] }
        if let named = fields.firstValue([
            "carriere", "careers", "data", "items", "elenco", "list",
        ]), named.arrayValue != nil {
            return extract(from: named)
        }
        if let anyArray = fields.values.first(where: { $0.arrayValue != nil }) {
            return extract(from: anyArray)
        }
        return []
    }
}

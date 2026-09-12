import Foundation

/// One enrolment.
///
/// A person has a single `codicePersona` and a matricola per enrolment — a
/// finished triennale and a starting magistrale are two careers, two
/// matricole, one human. Nearly every PoliMi endpoint is parameterised by
/// matricola, and the OAuth token is bound to one of them, so the closed
/// career's services refuse the token outright with "Utente non abilitato
/// Code: 6". Choosing the right one is not a preference; it is the difference
/// between the app working and not.
///
/// `GET {app}/v1/careers/list`. Field names verified from the official
/// bundle, which renders each row as `matricola`, `desc_tipo_carriera[lang]`
/// and `desc_stato_carriera[lang]`.
///
/// - Note: named `Career` in the domain but kept in `Enrolment.swift`, since
///   `Career.swift` is the gradebook and exam sittings.
nonisolated struct Career: Identifiable, Sendable, Hashable, Codable {
    var id: String { matricola }
    let matricola: String
    /// "Laurea Magistrale", where the payload says.
    let kind: String?
    /// "Attiva" / "Chiusa", as upstream words it.
    let status: String?

    /// Whether this enrolment is open. Everything follows from it: the active
    /// career is the one whose exam services will answer.
    var isActive: Bool {
        guard let status = status?.lowercased() else { return false }
        return status.contains("attiv") || status.contains("active")
            || status.contains("in corso")
    }

    var label: String {
        [kind, status].compactMap { $0 }.joined(separator: " · ")
    }

    /// The career to use when the user has not chosen: the active one, else
    /// the first. Never nil for a non-empty list — leaving it unset would
    /// send every request without a matricola.
    static func preferred(in careers: [Career]) -> Career? {
        careers.first(where: \.isActive) ?? careers.first
    }
}

/// `/v1/careers/list` — an array, or an array behind a key.
nonisolated struct CareersResponse: Decodable, Sendable {
    let careers: [Career]
    let raw: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        careers = CareersResponse.extract(from: value)
    }

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

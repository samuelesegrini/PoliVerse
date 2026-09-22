import Foundation
import OSLog

/// One marked script the student may look at on Servizi Online.
///
/// The sitting already says whether corrections exist — `hasCorrezioni` on
/// `iscrizioneAttiva` — and until now the app could only say so and send the
/// student to the web. This is the list behind that flag.
nonisolated struct Correction: Identifiable, Sendable, Equatable {
    /// The document's identifier, which `/v1/prove/correzione/{id}` takes.
    let id: String
    /// What the document is called, where the service names it.
    let name: String?
    /// When it was published, where the service dates it.
    let date: Date?
    /// The file's type as the service words it, for example `application/pdf`.
    let contentType: String?

    /// The name to show: the service's own, or a fallback naming the document
    /// by what it is.
    var title: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return String(localized: "Elaborato corretto")
        }
        return name
    }
}

/// Reads the list of marked scripts for a sitting.
///
/// - Important: The response shape is **not verified**. `docs/polimi-api-research.md`
///   §4c lists the path from the official client's own bundle, and says of every
///   shape on that host: "Response shapes beyond these field names are INFERRED."
///   So the list is decoded through ``JSONValue`` and read by candidate key
///   rather than through a `Codable` struct that would fail whole on one
///   unexpected name, and every field but the id is optional. A response this
///   reader cannot make sense of yields an empty list, which the screen shows
///   as "nothing to see here yet" — the state it had before.
nonisolated enum CorrectionsSource {
    /// Diagnostic log for this type, under the `career` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "career")

    /// The keys the id may arrive under.
    private static let idKeys = ["id", "idCorrezione", "c_correzione", "idDocumento", "idFile"]
    /// The keys the name may arrive under.
    private static let nameKeys = ["nome", "nomeFile", "descrizione", "titolo", "fileName", "name"]
    /// The keys the date may arrive under.
    private static let dateKeys = ["data", "dataPubblicazione", "dataCaricamento", "d_pubblicazione", "date"]
    /// The keys the content type may arrive under.
    private static let typeKeys = ["contentType", "mimeType", "tipoFile", "formato"]
    /// The keys a wrapped list may arrive under, when the body is an object
    /// rather than an array.
    private static let listKeys = ["correzioni", "elenco", "data", "items", "list", "result"]

    /// Fetches the marked scripts for one sitting.
    ///
    /// - Parameters:
    ///   - examID: The sitting's `c_appello`.
    ///   - http: The transport.
    /// - Returns: The documents, or an empty list when there are none or the
    ///   answer cannot be read.
    /// - Throws: Whatever the transport throws, so the screen can say the
    ///   service refused rather than that there is nothing there.
    static func corrections(forExam examID: Int, http: any HTTP) async throws -> [Correction] {
        let data = try await http.data(
            for: APIRequest(host: .iae, path: "/v1/prove/correzioni/\(examID)"))
        let body = try await BackgroundJSON.decode(JSONValue.self, from: data)
        let rows = list(in: body)
        let corrections = rows.compactMap(correction)
        log.notice("corrections for \(examID, privacy: .public): \(rows.count, privacy: .public) rows, \(corrections.count, privacy: .public) usable")
        return corrections
    }

    /// The rows of the answer, whether it is a bare array or an object holding
    /// one under some name.
    ///
    /// - Parameter body: The decoded body.
    /// - Returns: The rows, or an empty list.
    static func list(in body: JSONValue) -> [JSONValue] {
        if let array = body.arrayValue { return array }
        guard let object = body.objectValue else { return [] }
        for key in listKeys {
            if let value = object.firstValue([key])?.arrayValue { return value }
        }
        return []
    }

    /// Reads one row.
    ///
    /// - Parameter row: The row.
    /// - Returns: The document, or `nil` when it carries no identifier — with
    ///   no id there is nothing to open, so there is nothing to list.
    static func correction(_ row: JSONValue) -> Correction? {
        guard let object = row.objectValue,
              let id = object.firstValue(idKeys)?.stringValue,
              !id.isEmpty
        else { return nil }
        return Correction(
            id: id,
            name: object.firstValue(nameKeys)?.stringValue,
            date: object.firstValue(dateKeys)?.stringValue.flatMap(PoliMiDate.parse),
            contentType: object.firstValue(typeKeys)?.stringValue)
    }
}

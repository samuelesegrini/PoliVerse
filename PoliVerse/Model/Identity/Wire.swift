import Foundation

/// The shape the profile endpoint sends for the signed-in student.

/// Wire shape of `GET /rest/jaf/internal/user`, kept separate from ``Student``
/// so the Italian field names never leak into the UI layer.
nonisolated struct PoliMiUserDTO: Decodable, Sendable {
    let codicePersona: String
    let matricola: String
    let nome: String
    let cognome: String
    let email: String
    let fotoURL: String?

    func toStudent() -> Student {
        Student(
            personCode: codicePersona,
            matricola: matricola,
            firstName: nome.capitalized,
            lastName: cognome.capitalized,
            email: email,
            photoURL: fotoURL.flatMap(URL.init(string:))
        )
    }
}

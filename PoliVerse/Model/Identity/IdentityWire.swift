import Foundation

/// The signed-in student as `GET /rest/jaf/internal/user` sends them.
///
/// Kept separate from ``Student`` so the endpoint's Italian field names do not reach
/// the rest of the app.
nonisolated struct PoliMiUserDTO: Decodable, Sendable {
    /// The person code, stable across careers.
    let codicePersona: String
    /// The enrolment number of the current career.
    let matricola: String
    /// Given name, as the registry holds it.
    let nome: String
    /// Surname, as the registry holds it.
    let cognome: String
    /// The institutional address.
    let email: String
    /// The profile photograph's address, when the account has one.
    let fotoURL: String?

    /// Converts the payload into a ``Student``, capitalising both names.
    ///
    /// - Returns: The student. An unparseable photo address becomes `nil`.
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

import Foundation

/// The signed-in student, as the app uses them.
///
/// Decoded from ``PoliMiUserDTO``, so the endpoint's Italian field names do not
/// reach the rest of the app.
nonisolated struct Student: Codable, Sendable, Identifiable, Equatable {
    /// ``personCode``, which identifies the person across careers.
    var id: String { personCode }

    /// `codicePersona`: stable across careers, and what anything remembered per person
    /// is keyed by.
    var personCode: String
    /// `matricola`: the enrolment number, and the key most endpoints are parameterised
    /// by. A person with several careers has one per career.
    var matricola: String
    /// Given name, capitalised.
    var firstName: String
    /// Surname, capitalised. The Manifesti service picks a teaching's alphabetical
    /// bracket from it.
    var lastName: String
    /// The institutional address.
    var email: String
    /// The profile photograph, when the account has one.
    var photoURL: URL?

    /// Given name and surname, space separated.
    var fullName: String { "\(firstName) \(lastName)" }

    /// The first letter of each name, upper-cased, for an avatar with no photograph.
    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }
}

import Foundation

/// The signed-in student.
nonisolated struct Student: Codable, Sendable, Identifiable, Equatable {
    var id: String { personCode }

    /// `codicePersona` — stable across careers, used for identity.
    var personCode: String
    /// `matricola` — the enrolment number, and the key most PoliMi endpoints
    /// are parameterised by. A person with several careers has several of these.
    var matricola: String
    var firstName: String
    var lastName: String
    var email: String
    var photoURL: URL?

    var fullName: String { "\(firstName) \(lastName)" }

    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }
}

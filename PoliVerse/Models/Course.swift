import Foundation

/// A teaching the student is enrolled in.
nonisolated struct Course: Identifiable, Sendable, Hashable {
    let id: String
    /// `xdescrizione` upstream — arrives SHOUTED, so normalise on the way in.
    let name: String
    let teacher: String
    let cfu: Int
    let semester: String
    let academicYear: String
    var isFavourite: Bool = false

    /// Deterministic accent so a course keeps the same colour between launches
    /// without persisting anything. PoliFemo shipped 23 MB of stock wallpapers
    /// to solve this; a hash is free.
    var colorSeed: Int { abs(id.hashValue) % 8 }

    /// "ARCHITETTURE DEI CALCOLATORI" reads badly in a title; fix it once here.
    static func normalise(_ raw: String) -> String {
        let lower = raw.lowercased()
        return lower.split(separator: " ").map { word -> String in
            // Keep Italian articles and prepositions lowercase mid-title.
            let minor: Set<String> = ["di", "dei", "delle", "della", "e", "ed", "in", "a", "al", "per", "con", "dai"]
            return minor.contains(String(word)) ? String(word) : word.capitalized
        }.joined(separator: " ")
    }
}

/// Wire shape of an entry in `/rest/v1/insegn` (the `iae` exams host).
nonisolated struct TeachingDTO: Decodable, Sendable {
    let c_insegn_piano: String
    let xdescrizione: String
    let docente_esame: String?
    let aa_freq: String
    let semestre_freq: String?

    func toCourse() -> Course {
        Course(
            id: c_insegn_piano,
            name: Course.normalise(xdescrizione),
            teacher: docente_esame?.capitalized ?? "—",
            cfu: 0, // not present on this endpoint; filled from the study plan
            semester: semestre_freq ?? "—",
            academicYear: aa_freq
        )
    }
}

nonisolated struct TeachingsResponse: Decodable, Sendable {
    let INSEGN: [TeachingDTO]
}

import Foundation

/// A teaching the student is enrolled in.
nonisolated struct Course: Identifiable, Sendable, Hashable, Codable {
    let id: String
    /// `xdescrizione` upstream — arrives SHOUTED, so normalise on the way in.
    let name: String
    let teacher: String
    let cfu: Int
    let semester: String
    let academicYear: String
    var teacherEmail: String?
    /// Moodle's own course id, when this course came from WeBeep.
    ///
    /// Having it removes the need to match a PoliMi course to a Moodle one by
    /// name, which was the weakest link in the materials lookup.
    var moodleID: Int?
    var isFavourite: Bool = false

    /// Deterministic accent so a course keeps the same colour between launches
    /// without persisting anything. PoliFemo shipped 23 MB of stock wallpapers
    /// to solve this; a hash is free.
    ///
    /// - Important: this must NOT use `hashValue`. Swift seeds string hashing
    ///   randomly per process, so `hashValue` gives a different answer on every
    ///   launch — the colours visibly reshuffled each time the app restarted.
    ///   FNV-1a is stable across processes and platforms.
    var colorSeed: Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % 8)
    }

    /// `isFavourite` is deliberately absent from the coding keys: it lives in
    /// `UserDefaults` and is reapplied on load, so a stale cache can never
    /// resurrect a favourite the user has since removed.
    private enum CodingKeys: String, CodingKey {
        case id, name, teacher, cfu, semester, academicYear, teacherEmail, moodleID
    }

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

extension Course {
    /// Builds a course from a WeBeep (Moodle) enrolment.
    ///
    /// WeBeep names courses like `"097785 - BASI DI DATI [2025-26]"`, so the
    /// leading code is pulled out where present — it is what PoliMi's own
    /// endpoints key on, and keeping the two identifiers aligned means a course
    /// from either source refers to the same thing.
    init(moodle: MoodleCourse) {
        let full = moodle.fullname
        let (code, title) = Course.splitCode(from: full)

        self.init(
            id: code ?? "moodle-\(moodle.id)",
            name: Course.normalise(title),
            teacher: "—",
            cfu: 0,
            semester: "—",
            academicYear: Course.academicYear(from: full) ?? "—",
            moodleID: moodle.id
        )
    }

    /// Splits `"097785 - BASI DI DATI [2025-26]"` into its code and title.
    static func splitCode(from fullname: String) -> (code: String?, title: String) {
        var title = fullname
        // Trim a trailing academic year in brackets.
        if let bracket = title.range(of: " [", options: .backwards) {
            title = String(title[title.startIndex..<bracket.lowerBound])
        }
        let parts = title.components(separatedBy: " - ")
        guard parts.count > 1 else { return (nil, title) }

        let candidate = parts[0].trimmingCharacters(in: .whitespaces)
        // A course code is all digits; anything else is part of the title.
        guard !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else {
            return (nil, title)
        }
        return (candidate, parts.dropFirst().joined(separator: " - "))
    }

    static func academicYear(from fullname: String) -> String? {
        guard
            let open = fullname.range(of: "[", options: .backwards),
            let close = fullname.range(of: "]", options: .backwards),
            open.upperBound < close.lowerBound
        else { return nil }
        return String(fullname[open.upperBound..<close.lowerBound])
    }
}

/// Wire shape of an entry in `/rest/v1/insegn` (the `iae` exams host).
///
/// One response carries both the course list and every exam sitting, so
/// `CourseService` and `CareerService` share a single fetch rather than
/// hitting the endpoint twice.
/// Everything is optional.
///
/// A single unexpected null in one teaching would otherwise fail the whole
/// array and produce an empty course list — indistinguishable, from the UI,
/// from having no courses.
nonisolated struct TeachingDTO: Decodable, Sendable {
    let c_insegn_piano: String?
    let c_classe_m: Int?
    let xdescrizione: String?
    let docente_esame: String?
    let docente_esame_mail: String?
    let aa_freq: String?
    let semestre_freq: String?
    let appelliEsame: [ExamDTO]?

    /// Falls back to the class code when the plan code is absent, since one of
    /// the two is what identifies a teaching.
    var identifier: String? {
        if let c_insegn_piano, !c_insegn_piano.isEmpty { return c_insegn_piano }
        return c_classe_m.map(String.init)
    }

    func toCourse() -> Course? {
        guard let identifier, let xdescrizione, !xdescrizione.isEmpty else { return nil }
        return Course(
            id: identifier,
            name: Course.normalise(xdescrizione),
            teacher: docente_esame?.capitalized ?? "—",
            cfu: 0, // not present on this endpoint; filled from the study plan
            semester: semestre_freq ?? "—",
            academicYear: aa_freq ?? "—",
            teacherEmail: docente_esame_mail
        )
    }

    func toExamSessions() -> [ExamSession] {
        guard let identifier else { return [] }
        return (appelliEsame ?? []).map {
            $0.toSession(
                courseName: xdescrizione ?? "—",
                courseCode: identifier,
                teacher: docente_esame
            )
        }
    }
}

nonisolated struct TeachingsResponse: Decodable, Sendable {
    let INSEGN: [TeachingDTO]?

    var teachings: [TeachingDTO] { INSEGN ?? [] }
}

import Foundation

/// One recorded lecture, as the recman archive lists it.
///
/// A row of `ArchivioListActivity.do`: when it was recorded, which teaching, what
/// kind of session and what it covered, and how long and heavy it is. The row's
/// play link carries a session token and is not kept here — see
/// ``RecordingsModel`` for how a recording is opened. See `docs/recordings.md`.
nonisolated struct Recording: Codable, Sendable, Identifiable, Hashable {
    /// The kind of session recorded, from the archive's "Forma didattica" column.
    enum Form: String, Codable, Sendable {
        case lecture, lab, exercise, other

        /// Reads the archive's label, in Italian or English, falling back to ``other``.
        ///
        /// - Parameter label: The cell's text.
        init(label: String) {
            switch label.lowercased() {
            case "lezione", "lecture", "lesson": self = .lecture
            case "laboratorio", "laboratory", "lab": self = .lab
            case "esercitazione", "exercise", "exercise session", "practice": self = .exercise
            default: self = .other
            }
        }

        /// The kind's name on screen.
        var title: String {
            switch self {
            case .lecture: String(localized: "Lezione")
            case .lab: String(localized: "Laboratorio")
            case .exercise: String(localized: "Esercitazione")
            case .other: String(localized: "Altro")
            }
        }
    }

    /// The archive's own id for the recording, from the play link's `transfer_id`.
    ///
    /// Stable across sessions, unlike the rest of that link.
    let transferID: Int
    /// The academic year as the archive writes it, normalised to `"2026/27"`.
    let academicYear: String
    /// When the recording started — not necessarily when the timetable slot did.
    let recordedAt: Date
    /// The six-digit teaching code the archive puts first in the course cell.
    let teachingCode: String
    /// The teaching's title, without the code and the lecturer.
    let courseTitle: String
    /// The lecturer in brackets after the title, when the cell names one.
    let lecturer: String?
    /// The kind of session.
    let form: Form
    /// What the lecturer wrote the recording covers, when anything.
    let topic: String?
    /// The length in minutes, as the archive rounds it.
    let minutes: Int?
    /// The size in megabytes, as the archive rounds it.
    let megabytes: Int?

    /// The recording's identity.
    var id: Int { transferID }

    /// The calendar year ``academicYear`` begins in, which is how ``Course`` years are
    /// compared regardless of their separator.
    var academicYearStart: String? {
        let prefix = academicYear.prefix(4)
        return prefix.count == 4 && prefix.allSatisfy(\.isNumber) ? String(prefix) : nil
    }
}

nonisolated extension Recording {
    /// The recordings of one course, newest first.
    ///
    /// Joined on the teaching code alone, which the archive states exactly. Every
    /// academic year is kept: a student who is resitting a course still wants last
    /// year's lectures, and the list says which year each is from.
    ///
    /// - Parameters:
    ///   - recordings: The whole archive.
    ///   - course: The course to match.
    /// - Returns: The course's recordings, or none when the course has no teaching code.
    static func of(_ course: Course, in recordings: [Recording]) -> [Recording] {
        guard let code = course.teachingCode else { return [] }
        return recordings
            .filter { $0.teachingCode == code }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
}

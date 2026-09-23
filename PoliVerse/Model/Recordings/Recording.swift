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

    /// Whether the recording belongs to the edition of the teaching that `course` is.
    ///
    /// A course is one year's edition; recordings of the same teaching from other
    /// years are the archive's, shown apart. A course whose year cannot be read
    /// counts every recording as its own.
    ///
    /// - Parameter course: The course, whose academic year is the edition's.
    /// - Returns: `true` when the years match, or the course's is unknown.
    func isOf(edition course: Course) -> Bool {
        guard let year = course.academicYearStart else { return true }
        return academicYearStart == year
    }
}

/// How far the student has got with one recording: kept on the device, not read
/// from anywhere.
///
/// Not a cache: nothing can fetch it again. It is kept per account alongside the
/// recordings, so signing out loses it — acceptable until the app has a store for
/// the student's own data (see `docs/recordings.md`, "Data model").
nonisolated struct RecordingProgress: Codable, Sendable, Equatable {
    /// The recording, by `transfer_id`.
    let transferID: Int
    /// Where the student stopped, in seconds.
    var position: Double = 0
    /// The recording's length, in seconds, as the player measured it.
    var duration: Double = 0
    /// Whether the recording counts as watched: played to nine tenths, or marked by
    /// hand.
    var completed = false
    /// When it was last played or marked.
    var updatedAt: Date = .now

    /// How much of the recording has been played, from 0 to 1.
    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Where to start again, or `nil` to start from the beginning: a recording
    /// watched to the end, or barely started, starts over.
    ///
    /// A few seconds before the stopping point, so the sentence cut off is heard
    /// again.
    var resumeAt: Double? {
        guard !completed, position > 30, duration == 0 || position < duration - 30 else { return nil }
        return max(position - 5, 0)
    }

    /// The share of a recording that counts as watching it.
    static let watchedFraction = 0.9

    /// Takes a position the player reported.
    ///
    /// - Parameters:
    ///   - position: Where the player is, in seconds.
    ///   - duration: The recording's length, in seconds, when known.
    mutating func played(to position: Double, of duration: Double) {
        guard position.isFinite, position >= 0 else { return }
        self.position = position
        if duration.isFinite, duration > 0 { self.duration = duration }
        if self.duration > 0, position >= self.duration * Self.watchedFraction { completed = true }
        updatedAt = .now
    }
}

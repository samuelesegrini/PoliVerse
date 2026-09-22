import Foundation

/// A teaching the student is enrolled in.
///
/// Built from either of two sources — WeBeep, through ``init(moodle:)``, or the exam
/// registration endpoint, through ``TeachingDTO/toCourse()`` — and ``code`` is what
/// lets the same teaching be recognised across both.
///
/// ``isFavourite`` is excluded from the coding keys: it belongs to WeBeep and is
/// reapplied on every load, so a stale cache cannot resurrect a favourite that has
/// since been removed on the web. ``OptimisticFlags`` carries an unsent change
/// across a relaunch instead.
nonisolated struct Course: Identifiable, Sendable, Hashable, Codable {
    /// Unique identity: `moodle-<id>` for a WeBeep course, the teaching's plan or class
    /// code for one from the exams endpoint.
    let id: String
    /// The teaching's name, normalised by ``normalise(_:)``. Arrives upper-cased
    /// upstream.
    let name: String
    /// The lecturer's name, or `"—"` when none is recorded.
    let teacher: String
    /// Credits. Zero from both fetch paths, since neither endpoint carries it; the study
    /// plan supplies it.
    let cfu: Int
    /// The semester, or `"—"` when not recorded.
    let semester: String
    /// The academic year, as `"2025/26"` or `"2025-26"`, or `"—"` when not recorded.
    let academicYear: String
    /// The lecturer's address, where the exams endpoint carries one.
    var teacherEmail: String?
    /// Moodle's own course id, when this course came from WeBeep.
    ///
    /// What every materials, forum and flag call is keyed by, so no PoliMi course has to
    /// be matched to a Moodle one by name.
    var moodleID: Int?
    /// The six-digit Politecnico teaching code, where the source carries one.
    ///
    /// Kept apart from ``id`` because it is not unique: one account can hold several
    /// WeBeep courses sharing a code — the same teaching across years, or a lecture and
    /// its laboratory.
    var code: String?
    /// Whether the course is starred on WeBeep. Owned by WeBeep and reapplied on every
    /// load; not persisted here.
    var isFavourite: Bool = false
    /// Whether the course is hidden from the normal list, mirroring Moodle's “Remove
    /// from view”. A hidden course is still reachable, just not in the way.
    var isHidden: Bool = false
    /// When the course starts, where WeBeep reports it. Used to derive the academic year
    /// when the title does not carry one.
    var startDate: Date?

    /// A stable accent index in `0..<8`, so a course keeps the same colour between
    /// launches without anything being persisted.
    ///
    /// Seeded from ``code`` where there is one, so a course keeps its colour whether it
    /// arrived from WeBeep or from the exams endpoint.
    ///
    /// - Important: computed with FNV-1a rather than `hashValue`. Swift seeds string
    ///   hashing per process, so `hashValue` would give a different answer on every
    ///   launch and the colours would reshuffle.
    var colorSeed: Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        // Seeded from the teaching code where there is one, so a course keeps
        // its colour whether it came from WeBeep or from PoliMi.
        for byte in (code ?? id).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % 8)
    }

    /// Every stored property except ``isFavourite``, which is WeBeep's and is reapplied
    /// rather than cached.
    private enum CodingKeys: String, CodingKey {
        case id, name, teacher, cfu, semester, academicYear, teacherEmail, moodleID, code
        case isHidden, startDate
    }

    /// Title-cases a shouted course name the way Italian wants it.
    ///
    /// `String.capitalized` gets two things wrong that appear constantly in these
    /// names: it capitalises after an apostrophe, turning `dell'informatica` into
    /// `Dell'Informatica`, and it capitalises articles and prepositions mid-title. This
    /// leaves the minor words lower case except as the first word, and capitalises the
    /// noun after an elided article without capitalising the article.
    ///
    /// - Parameter raw: The name as the endpoint sends it.
    /// - Returns: The title-cased name.
    static func normalise(_ raw: String) -> String {
        // Two things `String.capitalized` gets wrong for Italian, both of which
        // turn up constantly in real course names: it capitalises after an
        // apostrophe, making `dell'informatica` into `Dell'Informatica`, and it
        // capitalises articles and prepositions mid-title.
        let minor: Set<String> = [
            "di", "dei", "del", "delle", "della", "degli",
            "e", "ed", "in", "a", "al", "ai", "alla", "per", "con", "da", "dai",
            "dell'", "dall'", "all'", "sull'", "nell'", "l'", "d'",
        ]

        return raw.lowercased().split(separator: " ").enumerated().map { index, word in
            let text = String(word)
            // The first word always leads, whatever it is.
            if index > 0, minor.contains(text) { return text }

            // Capitalise only the first letter, so an elided article keeps the
            // noun after it capitalised without capitalising itself:
            // "dell'informatica" becomes "dell'Informatica".
            if let apostrophe = text.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
                let article = String(text[text.startIndex...apostrophe])
                let noun = String(text[text.index(after: apostrophe)...])
                let head = index > 0 && minor.contains(article)
                    ? article
                    : Course.upperFirst(article)
                return head + Course.upperFirst(noun)
            }
            return Course.upperFirst(text)
        }.joined(separator: " ")
    }

    /// Upper-cases the first character only, leaving the rest as written.
    ///
    /// - Parameter value: The word.
    /// - Returns: The word with its first character upper-cased.
    private static func upperFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }
}

/// Building a course from WeBeep, and reading the identifiers out of its title.
extension Course {
    /// Builds a course from a WeBeep enrolment.
    ///
    /// WeBeep names courses like `"097785 - BASI DI DATI [2025-26]"`, so the leading
    /// code is pulled out where present — it is what the Politecnico's own endpoints key
    /// on, which keeps a course from either source referring to the same teaching.
    ///
    /// Moodle's id becomes the identity, since it is the one value guaranteed unique.
    /// ``cfu``, ``teacher`` and ``semester`` are left empty, as Moodle carries none of
    /// them, and the favourite and hidden flags come straight from WeBeep.
    ///
    /// - Parameter moodle: The enrolment as Moodle sends it.
    init(moodle: MoodleCourse) {
        let full = moodle.fullname
        let (code, title) = Course.splitCode(from: full)

        let start = moodle.startdate.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil
        }

        self.init(
            // Moodle's id is the identity: the only value guaranteed unique.
            id: "moodle-\(moodle.id)",
            name: Course.normalise(title),
            teacher: "—",
            cfu: 0,
            semester: "—",
            // The title's bracketed year is the more precise label when it is
            // there; the start date is the fallback.
            academicYear: Course.academicYear(from: full)
                ?? start.map(Course.academicYearLabel(for:))
                ?? "—",
            moodleID: moodle.id,
            code: code,
            // WeBeep owns these three states, so they come straight from it.
            isFavourite: moodle.isfavourite ?? false,
            isHidden: moodle.hidden ?? false,
            startDate: start
        )
    }

    /// Splits a WeBeep course title into its teaching code and its name.
    ///
    /// A trailing bracketed academic year is trimmed first. The leading segment counts
    /// as a code only when it is entirely digits; anything else is part of the title.
    ///
    /// - Parameter fullname: The title as WeBeep sends it.
    /// - Returns: The code, when there is one, and the title without it.
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

    /// The calendar year ``academicYear`` begins in — `"2025"` for `"2025-26"` or
    /// `"2025/26"`, which is how the manifesto names its years.
    ///
    /// `nil` when the value does not start with four digits.
    nonisolated var academicYearStart: String? {
        let prefix = academicYear.prefix(4)
        return prefix.count == 4 && prefix.allSatisfy(\.isNumber) ? String(prefix) : nil
    }

    /// The six-digit Politecnico teaching code, taken from ``code`` or ``id``, or `nil`
    /// when neither is one.
    nonisolated var teachingCode: String? {
        [code, id].compactMap { $0 }.first { $0.range(of: "^[0-9]{6}$", options: .regularExpression) != nil }
    }

    /// The academic year a date falls in, as `"2025/26"`.
    ///
    /// A teaching's year turns in September, so a January lecture belongs to the year
    /// that began the previous autumn. Exam sittings turn in October instead — see
    /// ``PoliMiDate/academicYear(ofSitting:calendar:)``.
    ///
    /// - Parameter date: The date to place.
    /// - Returns: The year label.
    nonisolated static func academicYearLabel(for date: Date) -> String {
        let calendar = PoliMiDate.romeCalendar
        let year = calendar.component(.year, from: date)
        let start = calendar.component(.month, from: date) >= 9 ? year : year - 1
        return "\(start)/\(String(format: "%02d", (start + 1) % 100))"
    }

    /// The bracketed academic year in a WeBeep course title.
    ///
    /// - Parameter fullname: The title as WeBeep sends it.
    /// - Returns: The text between the last brackets, or `nil` when there is none.
    static func academicYear(from fullname: String) -> String? {
        guard
            let open = fullname.range(of: "[", options: .backwards),
            let close = fullname.range(of: "]", options: .backwards),
            open.upperBound < close.lowerBound
        else { return nil }
        return String(fullname[open.upperBound..<close.lowerBound])
    }
}

/// Matching a course against the timetable.
nonisolated extension Course {
    /// Whether an agenda entry is a lesson of this course.
    ///
    /// Matched by name, since the agenda carries no teaching code, and by either name
    /// containing the other, since the agenda titles a laboratory and its lecture
    /// differently from WeBeep.
    ///
    /// - Parameter event: The agenda entry to test.
    /// - Returns: `true` when the two name the same teaching. Always `false` when either
    ///   name is empty.
    func matches(_ event: AgendaEvent) -> Bool {
        let title = event.title.lowercased(), target = name.lowercased()
        guard !title.isEmpty, !target.isEmpty else { return false }
        return title.contains(target) || target.contains(title)
    }
}

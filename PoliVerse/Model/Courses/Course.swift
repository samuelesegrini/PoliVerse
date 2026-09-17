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
    /// The Politecnico teaching code, where the WeBeep title carries one.
    ///
    /// Kept separate from ``id`` because it is **not unique**: a real account
    /// has several WeBeep courses sharing a code — the same teaching across
    /// years, or a lecture and its lab. Using it as the identity made SwiftUI
    /// collapse those rows into one and warn about duplicate IDs.
    var code: String?
    var isFavourite: Bool = false
    /// Hidden from the normal list, mirroring Moodle's "Remove from view".
    /// Hidden courses are still reachable, just not in the way.
    var isHidden: Bool = false
    /// Start of the course, used to group by academic year.
    var startDate: Date?

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
        // Seeded from the teaching code where there is one, so a course keeps
        // its colour whether it came from WeBeep or from PoliMi.
        for byte in (code ?? id).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % 8)
    }

    /// `isFavourite` is deliberately absent from the coding keys: it lives in
    /// `UserDefaults` and is reapplied on load, so a stale cache can never
    /// resurrect a favourite the user has since removed.
    private enum CodingKeys: String, CodingKey {
        case id, name, teacher, cfu, semester, academicYear, teacherEmail, moodleID, code
        case isHidden, startDate
    }

    /// "ARCHITETTURE DEI CALCOLATORI" reads badly in a title; fix it once here.
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

    /// Uppercases the first character only, leaving the rest untouched.
    private static func upperFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
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

    /// The Politecnico year a date falls in, as `"2025/26"`.
    ///
    /// The academic year starts in autumn, so anything before September belongs
    /// to the year that began the previous calendar year — a January lecture is
    /// in 2025/26, not 2026/27.
    /// The year the course's academic year starts in, `2025` for "2025-26"
    /// or "2025/26" — how the manifesto names its years.
    nonisolated var academicYearStart: String? {
        let prefix = academicYear.prefix(4)
        return prefix.count == 4 && prefix.allSatisfy(\.isNumber) ? String(prefix) : nil
    }

    /// The six-digit Politecnico teaching code, where the course has one.
    nonisolated var teachingCode: String? {
        [code, id].compactMap { $0 }.first { $0.range(of: "^[0-9]{6}$", options: .regularExpression) != nil }
    }

    static func academicYearLabel(for date: Date) -> String {
        let calendar = PoliMiDate.romeCalendar
        let year = calendar.component(.year, from: date)
        let start = calendar.component(.month, from: date) >= 9 ? year : year - 1
        return "\(start)/\(String(format: "%02d", (start + 1) % 100))"
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

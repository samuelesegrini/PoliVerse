import Foundation

/// Picks the scheda that is the student's, among the manifesto rows a teaching code
/// returns.
///
/// One teaching serves several degree courses, and a split teaching has a scheda per
/// alphabetical bracket — a different lecturer, sometimes a different exam. The order of
/// preference is therefore: the student's own degree course where the career says which
/// it is, then the bracket their surname falls in, then the first row that has a scheda
/// at all.
nonisolated enum SyllabusPicker {
    /// The scheda that was picked, and how sure the choice is.
    ///
    /// Kept small enough to store — the degree course's name rather than its whole page — so
    /// a found scheda survives a relaunch.
    struct Pick: Sendable, Codable, Equatable {
        /// The degree course the chosen row belongs to.
        let degreeCourse: String?
        /// The module whose scheda to open.
        let module: ManifestoModule
        /// Whether the student's own degree course was found among the rows. When `false` this is
        /// the first row with a scheda, and the interface says so.
        let matchesDegree: Bool
        /// The modules of an integrated course, the entry first. Empty for a single-module
        /// teaching.
        ///
        /// The Politecnico publishes one scheda for the whole course, so the parts are listed
        /// rather than opened.
        var parts: [ManifestoModule] = []

        /// Creates a pick, dropping a `parts` list that names only the entry itself.
        ///
        /// - Parameters:
        ///   - degreeCourse: The degree course the row belongs to.
        ///   - module: The module whose scheda to open.
        ///   - matchesDegree: Whether the student's own degree course was found.
        ///   - parts: The modules of an integrated course.
        init(degreeCourse: String?, module: ManifestoModule, matchesDegree: Bool, parts: [ManifestoModule] = []) {
            self.degreeCourse = degreeCourse
            self.module = module
            self.matchesDegree = matchesDegree
            self.parts = parts.count > 1 ? parts : []
        }

        /// Whether the teaching is an integrated course with several modules.
        var isIntegrated: Bool { parts.count > 1 }

        /// Every lecturer of the course, the entry's first, each named once.
        var teachers: [String] {
            var names: [String] = []
            for name in ([module] + parts).flatMap({ $0.teachers.map(\.name) }) where !names.contains(name) {
                names.append(name)
            }
            return names
        }
    }

    /// Chooses the scheda that is the student's among several manifesto rows.
    ///
    /// Rows of the student's degree course are tried first, the service's own order kept
    /// within each group; within a row, the bracket the surname falls in wins over the first
    /// module with a scheda.
    ///
    /// - Parameters:
    ///   - details: The manifesto rows a teaching code returned.
    ///   - surname: The student's surname, which decides the bracket.
    ///   - degreeName: The student's degree course, where the career says which it is.
    /// - Returns: The pick, or `nil` when no row has a scheda at all.
    static func pick(_ details: [ManifestoDetail], surname: String?, degreeName: String?) -> Pick? {
        let degree = degreeName.map(key)
        // Stable: the service's order is kept within each group.
        let ordered = details.filter { matches($0, degree) } + details.filter { !matches($0, degree) }
        for detail in ordered {
            let withScheda = detail.modules.filter { $0.syllabusID != nil }
            let mine = surname.flatMap { name in withScheda.first { $0.covers(surname: name) } }
            if let module = mine ?? withScheda.first {
                return Pick(degreeCourse: detail.degreeCourse, module: module, matchesDegree: matches(detail, degree),
                            parts: parts(of: module, in: detail.modules))
            }
        }
        return nil
    }

    /// The modules of an integrated course: the entry, and those listed under it with no
    /// bracket of their own, up to the next bracketed entry.
    ///
    /// - Parameters:
    ///   - entry: The course's entry module.
    ///   - modules: Every module on the row, in the service's order.
    /// - Returns: The entry and its parts.
    static func parts(of entry: ManifestoModule, in modules: [ManifestoModule]) -> [ManifestoModule] {
        guard let start = modules.firstIndex(of: entry) else { return [entry] }
        var parts = [entry]
        for module in modules[modules.index(after: start)...] {
            guard module.scaglioneFrom == nil, module.scaglioneTo == nil else { break }
            parts.append(module)
        }
        return parts
    }

    /// The module whose scheda is the student's, on a row already known to be their degree
    /// course and plan.
    ///
    /// - Parameters:
    ///   - modules: The row's modules.
    ///   - bracket: A bracket the student chose, which wins outright.
    ///   - surname: The student's surname, which decides the bracket otherwise.
    /// - Returns: The chosen module, or `nil` when none has a scheda.
    static func module(in modules: [ManifestoModule], bracket: BracketChoice?, surname: String?) -> ManifestoModule? {
        let withScheda = modules.filter { $0.syllabusID != nil }
        let trim = { (text: String?) in text?.trimmingCharacters(in: .whitespaces).uppercased() }
        if let bracket, let chosen = withScheda.first(where: {
            trim($0.scaglioneFrom) == trim(bracket.from) && trim($0.scaglioneTo) == trim(bracket.to)
        }) {
            return chosen
        }
        if let surname, let mine = withScheda.first(where: { $0.covers(surname: surname) }) { return mine }
        return withScheda.first
    }

    /// Catalogue rows with the student's own degree course first, the service's order kept
    /// within each group — so the first row read is usually the answer.
    ///
    /// - Parameters:
    ///   - rows: The rows a teaching code returned.
    ///   - degreeName: The student's degree course, or `nil` to leave the order alone.
    /// - Returns: The reordered rows.
    static func ordered(_ rows: [ManifestoTeaching], degreeName: String?) -> [ManifestoTeaching] {
        guard let degreeName else { return rows }
        let mine = rows.filter { DegreeCourseMatch.matches($0.degreeCourse, plan: degreeName) }
        return mine + rows.filter { !DegreeCourseMatch.matches($0.degreeCourse, plan: degreeName) }
    }

    /// Whether a manifesto row belongs to a given degree course, compared on folded names.
    ///
    /// - Parameters:
    ///   - detail: The row.
    ///   - degree: The degree course's folded name.
    /// - Returns: `true` when the row's course name contains it.
    private static func matches(_ detail: ManifestoDetail, _ degree: String?) -> Bool {
        guard let degree, !degree.isEmpty, let course = detail.degreeCourse else { return false }
        return key(course).contains(degree)
    }

    /// Text folded to ignore case and diacritics, and lower-cased.
    ///
    /// - Parameter text: The text as written.
    /// - Returns: The comparable form.
    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

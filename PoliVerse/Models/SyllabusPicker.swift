import Foundation

/// Picks the scheda that is the student's, among the manifesto rows a
/// teaching code returns.
///
/// One teaching serves several degree courses, and a split teaching has a
/// scheda per bracket — different lecturer, sometimes different exam. So:
/// the student's degree course first, where the career says which it is;
/// then the bracket their surname falls in; then the first row that has a
/// scheda at all.
nonisolated enum SyllabusPicker {
    /// Kept small enough to store: the degree course's name, not its whole
    /// page, so a found scheda survives a relaunch.
    struct Pick: Sendable, Codable, Equatable {
        let degreeCourse: String?
        let module: ManifestoModule
        /// Whether the student's own degree course was found among the rows;
        /// otherwise this is the first row with a scheda, and the UI says so.
        let matchesDegree: Bool
        /// The modules of an integrated course, the entry first; empty for a
        /// single-module teaching. PoliMi publishes one scheda for the whole
        /// course, so the parts are listed rather than opened.
        var parts: [ManifestoModule] = []

        init(degreeCourse: String?, module: ManifestoModule, matchesDegree: Bool, parts: [ManifestoModule] = []) {
            self.degreeCourse = degreeCourse
            self.module = module
            self.matchesDegree = matchesDegree
            self.parts = parts.count > 1 ? parts : []
        }

        var isIntegrated: Bool { parts.count > 1 }

        /// Every lecturer of the course, the entry's first, each once.
        var teachers: [String] {
            var names: [String] = []
            for name in ([module] + parts).flatMap({ $0.teachers.map(\.name) }) where !names.contains(name) {
                names.append(name)
            }
            return names
        }
    }

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

    /// The modules of an integrated course: the entry, and those listed under
    /// it with no bracket of their own, up to the next bracketed entry.
    static func parts(of entry: ManifestoModule, in modules: [ManifestoModule]) -> [ManifestoModule] {
        guard let start = modules.firstIndex(of: entry) else { return [entry] }
        var parts = [entry]
        for module in modules[modules.index(after: start)...] {
            guard module.scaglioneFrom == nil, module.scaglioneTo == nil else { break }
            parts.append(module)
        }
        return parts
    }

    /// The module whose scheda is the student's, on a row already known to be
    /// their degree course and plan: the bracket they chose, else the one their
    /// surname falls in, else the first with a scheda.
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

    /// Rows of the student's degree course first, the service's order kept
    /// within each group: usually the first detail read is the answer.
    static func ordered(_ rows: [ManifestoTeaching], degreeName: String?) -> [ManifestoTeaching] {
        guard let degreeName else { return rows }
        let mine = rows.filter { DegreeCourseMatch.matches($0.degreeCourse, plan: degreeName) }
        return mine + rows.filter { !DegreeCourseMatch.matches($0.degreeCourse, plan: degreeName) }
    }

    private static func matches(_ detail: ManifestoDetail, _ degree: String?) -> Bool {
        guard let degree, !degree.isEmpty, let course = detail.degreeCourse else { return false }
        return key(course).contains(degree)
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

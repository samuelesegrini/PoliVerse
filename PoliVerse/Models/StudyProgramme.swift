import Foundation

/// The student's own place in the manifesto: degree course and approved plan.
///
/// The key the course pages lacked. Neither the career services nor WeBeep
/// give a degree course code or a plan code, so the programme is chosen once
/// — or located from the career's degree name and confirmed — and then every
/// scheda and every WeBeep page is read against that plan rather than guessed
/// from a name shared by dozens of degree courses.
nonisolated struct StudyProgramme: Sendable, Equatable, Codable {
    var selection: CatalogueSelection
    var degreeLabel: String
    var planLabel: String
    /// False while it is the app's guess from the career's degree name.
    var isConfirmed: Bool
    /// Brackets chosen per teaching code, when not the one the surname gives.
    var brackets: [String: BracketChoice] = [:]
    /// Brackets read from the lecturers of the student's WeBeep pages. Below
    /// a choice, above the surname: attending a lecturer's page is the
    /// clearest sign of whose lessons they follow.
    var inferredBrackets: [String: BracketChoice] = [:]
    /// Courses linked by hand to a teaching of the plan, course id to code,
    /// for the few that neither code nor name can place.
    var links: [String: String] = [:]
    /// Set when the records stopped fitting it — a new degree course, a plan
    /// gone from the manifesto — so the student is asked again.
    var needsReview = false

    /// The bracket a teaching is read in, if not the surname's.
    func bracket(for code: String) -> BracketChoice? {
        brackets[code] ?? inferredBrackets[code]
    }

    /// The plan page of a given academic year: a course taken in 2025/26 is
    /// in the 2025/26 manifesto, under the same degree course and plan.
    func selection(forYear year: String?) -> CatalogueSelection {
        guard let year else { return selection }
        return selection.setting(.year, to: year)
    }
}

/// Programmes in the defaults, one per matricola: a bachelor's and a master's
/// career are two programmes, and one must never stand in for the other.
nonisolated struct StudyProgrammeStore: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func programme(for matricola: String) -> StudyProgramme? {
        guard let data = defaults.data(forKey: key(matricola)) else { return nil }
        return try? JSONDecoder().decode(StudyProgramme.self, from: data)
    }

    func save(_ programme: StudyProgramme?, for matricola: String) {
        write(programme, key(matricola))
    }

    /// Another plan the student follows in one academic year — the master's
    /// courses seen while signed in with the bachelor's matricola.
    func otherProgramme(for matricola: String, year: String) -> StudyProgramme? {
        guard let data = defaults.data(forKey: key(matricola) + "-other-" + year) else { return nil }
        return try? JSONDecoder().decode(StudyProgramme.self, from: data)
    }

    func saveOther(_ programme: StudyProgramme?, for matricola: String, year: String) {
        write(programme, key(matricola) + "-other-" + year)
    }

    private func write(_ programme: StudyProgramme?, _ key: String) {
        guard let programme, let data = try? JSONEncoder().encode(programme) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private func key(_ matricola: String) -> String { "studyProgramme-\(matricola)" }
}

/// Which teaching of the plan a course is.
///
/// By code first — WeBeep titles and `idnumber` often carry it — then by name,
/// but only when exactly one teaching of the plan has it: "Analisi Matematica"
/// alone is two teachings, and a wrong scheda is worse than none.
nonisolated enum PlanCourseMatch {
    static func match(codes: [String], name: String, in plan: [PlanTeaching]) -> PlanTeaching? {
        if let byCode = plan.first(where: { codes.contains($0.teaching.code) }) { return byCode }
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        let exact = plan.filter { key($0.teaching.name) == wanted }
        if exact.count == 1 { return exact[0] }
        let containing = plan.filter { wanted.contains(key($0.teaching.name)) }
        return containing.count == 1 ? containing[0] : nil
    }

    /// Folded and stripped of the bracketed year and punctuation WeBeep adds.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// The programme the student's own records point to.
///
/// The libretto lists teaching codes; each plan page lists teaching codes. The
/// plan sharing most of them is the student's, however the degree course is
/// named — which is what makes this better than any match by name.
nonisolated enum ProgrammeInference {
    struct Result: Sendable, Equatable {
        let selection: CatalogueSelection
        let overlap: Int
        /// Enough shared teachings to take it as the answer without asking.
        let isConfident: Bool
        /// Every plan sharing as many, the answer among them, in order.
        var tied: [CatalogueSelection] = []
    }

    static func best(libretto: Set<String>, candidates: [(CatalogueSelection, [String])]) -> Result? {
        guard !libretto.isEmpty else { return nil }
        let scored = candidates.map { selection, codes in (selection, libretto.intersection(codes).count) }
        guard let top = scored.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return nil }
        let runnerUp = scored.filter { $0.0 != top.0 }.map(\.1).max() ?? 0
        let confident = top.1 >= 3 && Double(top.1) >= Double(min(libretto.count, 10)) * 0.5 && top.1 > runnerUp
        let tied = scored.filter { $0.1 == top.1 }.map(\.0)
        return Result(selection: tied.first ?? top.0, overlap: top.1, isConfident: confident, tied: tied)
    }

    /// False once a libretto with enough rows shares nothing with the plan.
    static func stillFits(libretto: Set<String>, plan: Set<String>) -> Bool {
        guard libretto.count >= 3, !plan.isEmpty else { return true }
        return !libretto.isDisjoint(with: plan)
    }
}

/// The bracket a WeBeep page belongs to, from its lecturers.
nonisolated enum BracketInference {
    static func bracket(contacts: [String], brackets: [BracketChoice]) -> BracketChoice? {
        let people = contacts.map(tokens)
        let matching = brackets.filter { bracket in
            bracket.teachers.map(tokens).contains { teacher in
                people.contains { person in person.intersection(teacher).count >= min(2, teacher.count) }
            }
        }
        return matching.count == 1 ? matching[0] : nil
    }

    /// Names as sets of words, so "De Martino Antonino" and "Antonino De
    /// Martino" are the same person.
    private static func tokens(_ name: String) -> Set<String> {
        Set(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 1 })
    }
}

/// The degree courses and plans that offer a teaching, and which of them is
/// the student's when it is not the programme in use.
nonisolated enum PlanCandidates {
    static func distinct(_ rows: [ManifestoTeaching]) -> [ManifestoTeaching] {
        var seen: Set<String> = []
        return rows.filter { seen.insert("\($0.courseCode)/\($0.planCode ?? "")").inserted }
    }

    static func school(named name: String, in options: [CatalogueOption]) -> String? {
        let key = { (text: String) in PlanCourseMatch.key(text) }
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        return options.first { key($0.label) == wanted || key($0.label).hasPrefix(wanted + " ") }?.value
    }

    /// The candidate sharing most of the student's courses of that year.
    ///
    /// By degree course first: plans of one degree course share a teaching's
    /// brackets, different degree courses do not — that difference is the
    /// wrong lecturer. The teaching itself is in every candidate, so a degree
    /// course is an answer only with another course in common and no tie.
    static func best(enrolled: Set<String>, candidates: [(CatalogueSelection, [String])]) -> CatalogueSelection? {
        let scored = candidates.map { ($0.0, enrolled.intersection($0.1).count) }
        var byDegree: [String: Int] = [:]
        for (selection, score) in scored { byDegree[selection.degree] = max(byDegree[selection.degree] ?? 0, score) }
        guard let top = byDegree.values.max(), top >= 2, byDegree.values.filter({ $0 == top }).count == 1 else { return nil }
        return scored.first { $0.1 == top }?.0
    }

    /// The first plan of each degree course sharing the top score, when more
    /// than one degree course does — for settling the tie another way.
    static func tied(enrolled: Set<String>, candidates: [(CatalogueSelection, [String])]) -> [CatalogueSelection] {
        let scored = candidates.map { ($0.0, enrolled.intersection($0.1).count) }
        guard let top = scored.map(\.1).max(), top >= 1 else { return [] }
        var seen: Set<String> = []
        return scored.filter { $0.1 == top && seen.insert($0.0.degree).inserted }.map(\.0)
    }
}

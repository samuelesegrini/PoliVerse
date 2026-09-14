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
        guard let programme, let data = try? JSONEncoder().encode(programme) else {
            defaults.removeObject(forKey: key(matricola))
            return
        }
        defaults.set(data, forKey: key(matricola))
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

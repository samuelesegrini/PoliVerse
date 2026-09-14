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
    struct Pick: Sendable {
        let detail: ManifestoDetail
        let module: ManifestoModule
        /// Whether the student's own degree course was found among the rows;
        /// otherwise this is the first row with a scheda, and the UI says so.
        let matchesDegree: Bool
    }

    static func pick(_ details: [ManifestoDetail], surname: String?, degreeName: String?) -> Pick? {
        let degree = degreeName.map(key)
        // Stable: the service's order is kept within each group.
        let ordered = details.filter { matches($0, degree) } + details.filter { !matches($0, degree) }
        for detail in ordered {
            let withScheda = detail.modules.filter { $0.syllabusID != nil }
            let mine = surname.flatMap { name in withScheda.first { $0.covers(surname: name) } }
            if let module = mine ?? withScheda.first {
                return Pick(detail: detail, module: module, matchesDegree: matches(detail, degree))
            }
        }
        return nil
    }

    private static func matches(_ detail: ManifestoDetail, _ degree: String?) -> Bool {
        guard let degree, !degree.isEmpty, let course = detail.degreeCourse else { return false }
        return key(course).contains(degree)
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

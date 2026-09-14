import Foundation

/// Why a WeBeep course is on the student's list.
///
/// WeBeep enrols by codice persona, not matricola, and Moodle's
/// `core_enrol_get_users_courses` says nothing about how an enrolment came
/// about. A student finishing a bachelor's while enrolled "con riserva" in a
/// master's sees both careers' courses mixed with any they joined out of
/// curiosity. The only thing to go on is each career's study plan: a heuristic,
/// so the student can always correct it.
nonisolated enum EnrolmentOrigin: Sendable, Hashable {
    case currentPlan
    case otherCareer(String)
    case outsidePlan
    /// Outside every plan, on a page that takes self-enrolment: most likely
    /// joined out of interest.
    case selfEnrolled
    case unknown

    /// One career's plan, as its libretto lists it.
    struct Plan: Sendable {
        let matricola: String
        let isCurrent: Bool
        let codes: Set<String>
        /// Normalised with ``Course/normalise(_:)``, upper-cased.
        let names: Set<String>

        init(matricola: String, isCurrent: Bool, codes: Set<String>, names: Set<String>) {
            self.matricola = matricola
            self.isCurrent = isCurrent
            self.codes = codes
            self.names = Set(names.map(EnrolmentOrigin.key))
        }

        init(matricola: String, isCurrent: Bool, libretto: [LibrettoExam]) {
            self.init(matricola: matricola, isCurrent: isCurrent,
                      codes: Set(libretto.map(\.id)), names: Set(libretto.map(\.name)))
        }

        var isEmpty: Bool { codes.isEmpty && names.isEmpty }

        func contains(codes candidates: [String], name: String) -> Bool {
            if candidates.contains(where: codes.contains) { return true }
            return names.contains(EnrolmentOrigin.key(name))
        }
    }

    enum Override: String, Sendable, Codable {
        case plan, byChoice
    }

    static func classify(codes: [String], name: String, plans: [Plan], override: Override?,
                         selfEnrolmentOpen: Bool?) -> EnrolmentOrigin {
        switch override {
        case .plan: return .currentPlan
        case .byChoice: return .outsidePlan
        case nil: break
        }
        if let current = plans.first(where: \.isCurrent), current.contains(codes: codes, name: name) {
            return .currentPlan
        }
        if let other = plans.first(where: { !$0.isCurrent && $0.contains(codes: codes, name: name) }) {
            return .otherCareer(other.matricola)
        }
        guard let current = plans.first(where: \.isCurrent), !current.isEmpty else { return .unknown }
        return selfEnrolmentOpen == true ? .selfEnrolled : .outsidePlan
    }

    /// Six-digit teaching codes in whatever WeBeep carries: the title,
    /// `idnumber`, `shortname`.
    static func codes(in fields: [String?]) -> [String] {
        var found: [String] = []
        for field in fields.compactMap({ $0 }) {
            // Runs of digits, kept only when exactly six long.
            for run in field.split(whereSeparator: { !$0.isNumber }) where run.count == 6 && !found.contains(String(run)) {
                found.append(String(run))
            }
        }
        return found
    }

    static func key(_ name: String) -> String {
        Course.normalise(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
    }
}

/// Corrections the student made, per WeBeep course id.
enum EnrolmentOverrides {
    private static let key = "enrolmentOriginOverrides"

    static func all() -> [String: EnrolmentOrigin.Override] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: EnrolmentOrigin.Override].self, from: data)
        else { return [:] }
        return decoded
    }

    static func set(_ value: EnrolmentOrigin.Override?, for courseID: String) {
        var current = all()
        current[courseID] = value
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: key) }
    }
}

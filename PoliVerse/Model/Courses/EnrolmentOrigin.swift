import Foundation

/// Why a WeBeep course is on the student's list.
///
/// WeBeep enrols by person code rather than by matricola, and Moodle says nothing
/// about how an enrolment came about. A student finishing a bachelor's while
/// enrolled in a master's therefore sees both careers' courses mixed with any they
/// joined out of interest.
///
/// ``classify(codes:name:plans:override:selfEnrolmentOpen:)`` decides from the
/// careers' study plans, which is a heuristic — so the student can always correct
/// it, and ``EnrolmentOverrides`` remembers the correction.
nonisolated enum EnrolmentOrigin: Sendable, Hashable {
    /// In the current career's study plan.
    case currentPlan
    /// In another career's study plan, carrying that career's matricola.
    case otherCareer(String)
    /// In no plan, on a page that does not take self-enrolment.
    case outsidePlan
    /// In no plan, on a page that takes self-enrolment: most likely joined out of
    /// interest.
    case selfEnrolled
    /// Undecidable, because the current career's plan has not been read yet.
    case unknown

    /// One career's study plan, as the codes and names its libretto lists.
    struct Plan: Sendable {
        /// The career this plan belongs to.
        let matricola: String
        /// Whether this is the career currently in use.
        let isCurrent: Bool
        /// The plan's teaching codes.
        let codes: Set<String>
        /// The plan's teaching names, normalised by ``EnrolmentOrigin/key(_:)``.
        let names: Set<String>

        /// Creates a plan from codes and names.
        ///
        /// - Parameters:
        ///   - matricola: The career this plan belongs to.
        ///   - isCurrent: Whether it is the career in use.
        ///   - codes: The plan's teaching codes.
        ///   - names: The plan's teaching names, normalised on the way in.
        init(matricola: String, isCurrent: Bool, codes: Set<String>, names: Set<String>) {
            self.matricola = matricola
            self.isCurrent = isCurrent
            self.codes = codes
            self.names = Set(names.map(EnrolmentOrigin.key))
        }

        /// Creates a plan from a libretto.
        ///
        /// - Parameters:
        ///   - matricola: The career this plan belongs to.
        ///   - isCurrent: Whether it is the career in use.
        ///   - libretto: The career's recorded teachings.
        init(matricola: String, isCurrent: Bool, libretto: [LibrettoExam]) {
            self.init(matricola: matricola, isCurrent: isCurrent,
                      codes: Set(libretto.map(\.id)), names: Set(libretto.map(\.name)))
        }

        /// `true` when the plan has not been read, which classification treats as
        /// ``EnrolmentOrigin/unknown`` rather than as “outside the plan”.
        var isEmpty: Bool { codes.isEmpty && names.isEmpty }

        /// Whether this plan contains a teaching, by code or by normalised name.
        ///
        /// - Parameters:
        ///   - candidates: Codes found in the WeBeep course.
        ///   - name: The WeBeep course's name.
        /// - Returns: `true` when any code matches, or the name does.
        func contains(codes candidates: [String], name: String) -> Bool {
            if candidates.contains(where: codes.contains) { return true }
            return names.contains(EnrolmentOrigin.key(name))
        }
    }

    /// A correction the student made to a classification.
    enum Override: String, Sendable, Codable {
        /// `plan` forces ``EnrolmentOrigin/currentPlan``; `byChoice` forces
        /// ``EnrolmentOrigin/outsidePlan``.
        case plan, byChoice
    }

    /// Decides why a WeBeep course is on the list.
    ///
    /// An override wins outright. Otherwise the current career's plan is checked, then
    /// the other careers'. A teaching in none of them is ``selfEnrolled`` when the page
    /// takes self-enrolment and ``outsidePlan`` otherwise — unless the current plan has
    /// not been read, which yields ``unknown``.
    ///
    /// - Parameters:
    ///   - codes: Teaching codes found in the WeBeep course.
    ///   - name: The WeBeep course's name.
    ///   - plans: The careers' study plans.
    ///   - override: The student's own correction, if any.
    ///   - selfEnrolmentOpen: Whether the course page takes self-enrolment.
    /// - Returns: The classification.
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

    /// The six-digit teaching codes appearing in whatever WeBeep carries — the title,
    /// `idnumber`, `shortname`.
    ///
    /// - Parameter fields: The fields to search. `nil` fields are ignored.
    /// - Returns: The distinct six-digit runs found, in order.
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

    /// A teaching name reduced to its comparable form: title-cased, folded to ignore
    /// case and diacritics, then upper-cased.
    ///
    /// - Parameter name: The name as its source spells it.
    /// - Returns: The comparable form.
    static func key(_ name: String) -> String {
        Course.normalise(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
    }
}

/// The classifications the student corrected, persisted per WeBeep course id in
/// `UserDefaults`.
enum EnrolmentOverrides {
    /// Defaults key the overrides are stored under.
    private static let key = "enrolmentOriginOverrides"

    /// Every stored correction.
    ///
    /// - Returns: The corrections by ``Course/id``. Empty when none are stored or they
    ///   will not decode.
    static func all() -> [String: EnrolmentOrigin.Override] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: EnrolmentOrigin.Override].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Records or removes one correction.
    ///
    /// - Parameters:
    ///   - value: The correction, or `nil` to return to the heuristic.
    ///   - courseID: The ``Course/id`` it applies to.
    static func set(_ value: EnrolmentOrigin.Override?, for courseID: String) {
        var current = all()
        current[courseID] = value
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: key) }
    }
}

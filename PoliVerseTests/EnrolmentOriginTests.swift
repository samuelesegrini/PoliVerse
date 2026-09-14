import Foundation
import Testing
@testable import PoliVerse

/// Why a WeBeep course is on the list. Moodle does not say how a student was
/// enrolled, so this is read against each career's study plan: a course in
/// the plan of the career in use, in another career's plan, or in neither.
@Suite("Enrolment origin")
struct EnrolmentOriginTests {
    private let bachelor = EnrolmentOrigin.Plan(matricola: "986617", isCurrent: true,
                                                codes: ["052496"], names: ["ANALISI MATEMATICA 1"])
    private let master = EnrolmentOrigin.Plan(matricola: "337940", isCurrent: false,
                                              codes: ["099999"], names: ["MACHINE LEARNING"])

    private func origin(_ code: String?, _ name: String, plans: [EnrolmentOrigin.Plan]? = nil,
                        override: EnrolmentOrigin.Override? = nil) -> EnrolmentOrigin {
        EnrolmentOrigin.classify(code: code, name: name, plans: plans ?? [bachelor, master], override: override)
    }

    @Test("A code in the current plan is the current career's")
    func current() { #expect(origin("052496", "Qualcosa") == .currentPlan) }

    @Test("A name in the current plan matches when the codes do not agree")
    func byName() { #expect(origin(nil, "Analisi Matematica 1") == .currentPlan) }

    @Test("A course in another career's plan names that career")
    func otherCareer() { #expect(origin("099999", "Machine Learning") == .otherCareer("337940")) }

    @Test("Neither plan: probably enrolled by choice")
    func outside() { #expect(origin("012345", "Storia dell'architettura") == .outsidePlan) }

    @Test("Without the current plan nothing can be said")
    func unknownWithoutPlan() {
        let empty = EnrolmentOrigin.Plan(matricola: "986617", isCurrent: true, codes: [], names: [])
        #expect(origin("012345", "X", plans: [empty]) == .unknown)
    }

    @Test("The student's own word wins")
    func overrides() {
        #expect(origin("012345", "X", override: .plan) == .currentPlan)
        #expect(origin("052496", "X", override: .byChoice) == .outsidePlan)
    }
}

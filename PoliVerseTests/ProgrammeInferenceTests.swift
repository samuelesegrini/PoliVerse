import Foundation
import Testing
@testable import PoliVerse

/// Finding the student's degree course and plan from their own records, and
/// noticing when those records stop fitting it.
@Suite("Programme inference")
struct ProgrammeInferenceTests {
    private func selection(_ plan: String) -> CatalogueSelection {
        CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: "531", plan: plan)
    }

    @Test("The plan sharing most teachings with the libretto wins")
    func best() throws {
        let libretto: Set = ["1", "2", "3", "4", "5"]
        let result = try #require(ProgrammeInference.best(libretto: libretto, candidates: [
            (selection("IT1"), ["1", "2", "3", "4", "9"]),
            (selection("IOL"), ["1", "2", "8"]),
        ]))
        #expect(result.selection.plan == "IT1")
        #expect(result.overlap == 4)
        #expect(result.isConfident)
    }

    @Test("A tie is reported, so the career's track can settle it")
    func tie() throws {
        let result = try #require(ProgrammeInference.best(libretto: ["1", "2", "3"], candidates: [
            (selection("I3C"), ["1", "2", "3", "7"]), (selection("I3I"), ["1", "2", "3", "8"]),
        ]))
        #expect(!result.isConfident)
        #expect(result.tied.map(\.plan) == ["I3C", "I3I"])
    }

    @Test("A thin overlap is a guess, not an answer")
    func weak() throws {
        let result = try #require(ProgrammeInference.best(libretto: ["1", "2", "3", "4", "5", "6"],
                                                          candidates: [(selection("IT1"), ["1", "9"])]))
        #expect(!result.isConfident)
        #expect(ProgrammeInference.best(libretto: ["1"], candidates: [(selection("IT1"), ["9"])]) == nil)
        #expect(ProgrammeInference.best(libretto: [], candidates: [(selection("IT1"), ["9"])]) == nil)
    }

    @Test("A programme stops fitting once the libretto shares nothing with it")
    func stillFits() {
        #expect(ProgrammeInference.stillFits(libretto: ["1", "2", "3"], plan: ["3", "7"]))
        #expect(!ProgrammeInference.stillFits(libretto: ["1", "2", "3"], plan: ["7", "8"]))
        // Too little to judge: a first-year libretto, or a plan not read yet.
        #expect(ProgrammeInference.stillFits(libretto: ["1"], plan: ["7"]))
        #expect(ProgrammeInference.stillFits(libretto: ["1", "2", "3"], plan: []))
    }

    private func option(_ value: String, _ label: String, _ group: String) -> CatalogueOption {
        CatalogueOption(value: value, label: label, group: group)
    }

    @Test("The exact name beats a longer one containing it, and the career's level decides between equals")
    func degreeChoice() {
        let options = [option("1", "Ingegneria Informatica Online (1)", "Laurea di Primo Livello - ord. 270"),
                       option("531", "Ingegneria Informatica (531)", "Laurea di Primo Livello - ord. 96/23"),
                       option("600", "Ingegneria Informatica (600)", "Laurea Magistrale - ord. 96/23")]
        #expect(DegreeCourseMatch.best(options, name: "Ingegneria Informatica", kind: "Laurea")?.value == "531")
        #expect(DegreeCourseMatch.best(options, name: "Ingegneria Informatica", kind: "Laurea Magistrale")?.value == "600")
        #expect(DegreeCourseMatch.best(options, name: "Ingegneria Informatica", kind: nil)?.value == "531")
        #expect(DegreeCourseMatch.best(options, name: "Design", kind: nil) == nil)
    }

    @Test("A WeBeep lecturer names the bracket, in either name order")
    func bracketFromLecturer() {
        let brackets = [BracketChoice(from: "A", to: "CON", teachers: ["Cipriani Fabio Eugenio Giovanni"]),
                        BracketChoice(from: "CON", to: "FOT", teachers: ["De Martino Antonino"])]
        #expect(BracketInference.bracket(contacts: ["Antonino De Martino"], brackets: brackets)?.from == "CON")
        #expect(BracketInference.bracket(contacts: ["Mario Rossi"], brackets: brackets) == nil)
        // Two brackets' lecturers on one page: no single answer.
        #expect(BracketInference.bracket(contacts: ["Antonino De Martino", "Fabio Cipriani"], brackets: brackets) == nil)
    }

    @Test("Codes in the plan header are read when present")
    func headerCodes() throws {
        let json = #"{"descrizioneCDL":"Ingegneria Informatica","k_corso_la":531,"k_indir":"IT1"}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let header = try #require(StudyPlanHeader(value: value))
        #expect(header.degreeCode == "531")
        #expect(header.planCode == "IT1")
    }

    @Test("A plan page survives the disk cache")
    func planRoundTrip() throws {
        let row = PlanTeaching(teaching: ManifestoTeaching(code: "082740", name: "ANALISI", courseCode: "531", planCode: "IT1",
                                                           idItemOfferta: "1", idRiga: "2", semester: "1", year: "2026",
                                                           credits: 10, school: "225", degreeCourse: nil),
                               yearOfCourse: "1", credits: 10, group: "TABA", hasSections: false)
        let decoded = try JSONDecoder().decode([PlanTeaching].self, from: JSONEncoder().encode([row]))
        #expect(decoded == [row])
    }
}

/// Courses outside the programme in use — a master's course while signed in
/// with the bachelor's matricola — read from the plan the student's other
/// courses of that year point to, not from the first degree course offering it.
@Suite("Other programmes")
struct OtherProgrammeTests {
    private func teaching(_ course: String, _ plan: String) -> ManifestoTeaching {
        ManifestoTeaching(code: "054443", name: "SOFTWARE ENGINEERING 2", courseCode: course, planCode: plan,
                          idItemOfferta: nil, idRiga: nil, semester: "1", year: "2026", credits: nil, school: nil,
                          degreeCourse: nil)
    }

    @Test("Each degree course and plan offering a teaching is one candidate")
    func candidates() {
        let rows = [teaching("511", "GEC"), teaching("511", "GEC"), teaching("542", "T2A"), teaching("542", "T2D")]
        #expect(PlanCandidates.distinct(rows).map { "\($0.courseCode)/\($0.planCode ?? "")" } == ["511/GEC", "542/T2A", "542/T2D"])
    }

    @Test("A school named on a teaching page is the cascade's school of that name")
    func school() {
        let options = [CatalogueOption(value: "222", label: "Scuola di Architettura Urbanistica Ingegneria delle Costruzioni (Arc. Urb. Ing. Cos.)", group: nil),
                       CatalogueOption(value: "225", label: "Scuola di Ingegneria Industriale e dell'Informazione (Ing. Ind-Inf)", group: nil)]
        #expect(PlanCandidates.school(named: "Scuola di Ingegneria Industriale e dell'Informazione", in: options) == "225")
        #expect(PlanCandidates.school(named: "Scuola del Design", in: options) == nil)
    }

    @Test("The plan with most of the student's courses of that year is theirs; one shared course is not enough")
    func scoring() throws {
        let t2a = CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: "542", plan: "T2A")
        let geo = CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: "511", plan: "GEC")
        let enrolled: Set = ["054443", "052496", "095946", "054298"]
        let best = try #require(PlanCandidates.best(enrolled: enrolled, candidates: [
            (geo, ["054443", "099999"]), (t2a, ["054443", "052496", "095946", "054298", "011111"]),
        ]))
        #expect(best == t2a)
        #expect(PlanCandidates.best(enrolled: ["054443"], candidates: [(geo, ["054443"]), (t2a, ["054443"])]) == nil)
    }

    /// Live, 2026-09-14: 054443 has the same brackets in every plan of 542
    /// (A–DAT, DAT–MOH, MOH–ZZZZ) and different ones in 560 (A–E, E–P,
    /// P–ZZZZ). The degree course decides; a tie between its plans does not matter.
    @Test("Plans of one degree course tying is still an answer; two degree courses tying is not")
    func degreeFirst() {
        let t2a = CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: "542", plan: "T2A")
        let t2i = t2a.setting(.plan, to: "T2I")
        let z2a = CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: "560", plan: "Z2A")
        let enrolled: Set = ["1", "2", "3", "4", "5"]
        #expect(PlanCandidates.best(enrolled: enrolled, candidates: [(t2a, ["1", "2", "3", "4", "5"]), (t2i, ["1", "2", "3", "4", "5"]),
                                                                    (z2a, ["1", "2", "3", "4"])]) == t2a)
        #expect(PlanCandidates.best(enrolled: enrolled, candidates: [(t2a, ["1", "2", "3"]), (z2a, ["1", "2", "3"])]) == nil)
        #expect(PlanCandidates.tied(enrolled: enrolled, candidates: [(t2a, ["1", "2", "3"]), (t2i, ["1", "2", "3"]),
                                                                    (z2a, ["1", "2", "3"])]) == [t2a, z2a])
    }
}

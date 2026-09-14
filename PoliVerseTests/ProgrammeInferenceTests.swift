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

    /// Live, 531 in 2025: IOL (online, all years) 6, I1C (Cremona) 5, IT1 3.
    @Test("Winning by one teaching is not confident")
    func narrow() throws {
        let result = try #require(ProgrammeInference.best(libretto: ["1", "2", "3", "4", "5", "6"], candidates: [
            (selection("IOL"), ["1", "2", "3", "4", "5", "6"]), (selection("I1C"), ["1", "2", "3", "4", "5"]),
        ]))
        #expect(result.selection.plan == "IOL")
        #expect(!result.isConfident)
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
/// with the bachelor's matricola.
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

}

/// The same, from the catalogue search alone: a search by code already lists
/// every degree course and plan offering the teaching, so the student's
/// degree course is the one offering most of their courses of that year.
@Suite("Degree course from searches")
struct SearchInferenceTests {
    private func row(_ code: String, _ degree: String, _ plan: String, heading: String? = nil) -> ManifestoTeaching {
        ManifestoTeaching(code: code, name: code, courseCode: degree, planCode: plan, idItemOfferta: nil, idRiga: nil,
                          semester: "1", year: "2026", credits: nil, school: nil,
                          degreeCourse: heading ?? "Ing. Ind-Inf (Mag.)(ord. 96/23) - MI (\(degree)) X")
    }

    @Test("The degree course offering most of the student's courses, and its plan offering most")
    func degree() throws {
        let offerings = [
            "054443": [row("054443", "511", "GEC"), row("054443", "542", "T2A"), row("054443", "542", "T2I"), row("054443", "560", "Z2A")],
            "095946": [row("095946", "542", "T2I"), row("095946", "557", "MMI")],
            "052496": [row("052496", "542", "T2I"), row("052496", "553", "MST")],
        ]
        let answer = try #require(SearchInference.row(for: "054443", offerings: offerings))
        #expect(answer.courseCode == "542")
        #expect(answer.planCode == "T2I")
    }

    @Test("With nothing else to go on, several degree courses are not an answer; one is")
    func alone() {
        let several = ["054443": [row("054443", "511", "GEC"), row("054443", "542", "T2A")]]
        #expect(SearchInference.row(for: "054443", offerings: several) == nil)
        #expect(SearchInference.tiedRows(for: "054443", offerings: several).map(\.courseCode) == ["511", "542"])
        let one = ["054443": [row("054443", "542", "T2A"), row("054443", "542", "T2I")]]
        #expect(SearchInference.row(for: "054443", offerings: one)?.planCode == "T2A")
    }

    @Test("The school comes from the result's heading, shared degree courses included")
    func school() {
        let options = [CatalogueOption(value: "1", label: "Scuola di Ingegneria Civile, Ambientale e Territoriale (Ing. Civ)", group: nil),
                       CatalogueOption(value: "225", label: "Scuola di Ingegneria Industriale e dell'Informazione (Ing. Ind-Inf)", group: nil)]
        #expect(SearchInference.school(heading: "Ing. Ind-Inf (Mag.)(ord. 96/23) - MI (542) Computer Science and Engineering", in: options) == "225")
        #expect(SearchInference.school(heading: "Ing. Civ, Ing. Ind-Inf (Mag.)(ord. 96/23) - MI (511) Geoinformatics Engineering", in: options) == "1")
        #expect(SearchInference.school(heading: "Design (1 liv.) - MI (1) X", in: options) == nil)
    }
}

/// Shapes from the diagnostic report of a real account, 2026-09-14: the
/// libretto has names and no teaching codes, the plan header names the level.
@Suite("Career payloads, as sent")
struct CareerPayloadTests {
    @Test("A libretto row keeps its English name; its id is the row, not a teaching code")
    func librettoRow() throws {
        let json = #"{"sostenuti":[{"id_riga":47314209,"descrizione":"ALGORITMI E PRINCIPI DELL'INFORMATICA","descrizione_eng":"ALGORITHMS AND PRINCIPLES OF COMPUTER SCIENCE","stato_esame":"S","voto_esame":"25","data_esame":1750197600000}],"daSostenere":[]}"#
        let exam = try #require(try JSONDecoder().decode(LibrettoResponse.self, from: Data(json.utf8)).allExams.first)
        #expect(exam.id == "47314209")
        #expect(exam.englishName == "ALGORITHMS AND PRINCIPLES OF COMPUTER SCIENCE")
    }

    @Test("The plan header gives the level, the English name and the plan's year")
    func header() throws {
        let json = #"{"aa":"2025/26","descrizioneCDL":"INGEGNERIA INFORMATICA","descrizioneCDL_ENG":"ENGINEERING OF COMPUTING SYSTEMS","tipoCorso":"LAUREA DI PRIMO LIVELLO","statusPiano":"Approvato"}"#
        let header = try #require(StudyPlanHeader(value: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
        #expect(header.course == "INGEGNERIA INFORMATICA")
        #expect(header.level == "LAUREA DI PRIMO LIVELLO")
        #expect(header.englishCourse == "ENGINEERING OF COMPUTING SYSTEMS")
        #expect(header.yearCode == "2025")
    }

    @Test("A libretto and a plan are compared by teaching name, in either language")
    func byName() {
        let libretto = LibrettoExam(id: "47314209", name: "Algoritmi e Principi dell'Informatica", grade: 25, hasLode: false,
                                    cfu: 10, date: nil, statusText: nil, isPassed: true,
                                    englishName: "ALGORITHMS AND PRINCIPLES OF COMPUTER SCIENCE")
        let keys = ProgrammeInference.keys(of: [libretto])
        #expect(keys.contains(PlanCourseMatch.key("ALGORITMI E PRINCIPI DELL'INFORMATICA")))
        #expect(keys.contains(PlanCourseMatch.key("Algorithms and principles of computer science")))
        #expect(!keys.contains("47314209"))
    }
}

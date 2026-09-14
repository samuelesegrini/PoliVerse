import Foundation
import Testing
@testable import PoliVerse

/// The student's own place in the manifesto — degree course and plan — and
/// what hangs off it: the scheda of each course, and which plan teaching a
/// WeBeep page is.
@Suite("Study programme")
struct StudyProgrammeTests {
    private func row(_ code: String, _ name: String, year: String = "1") -> PlanTeaching {
        PlanTeaching(teaching: ManifestoTeaching(code: code, name: name, courseCode: "531", planCode: "IT1",
                                                 idItemOfferta: nil, idRiga: nil, semester: "1", year: "2026",
                                                 credits: nil, school: nil, degreeCourse: nil),
                     yearOfCourse: year, credits: nil, group: nil, hasSections: false)
    }

    private var plan: [PlanTeaching] {
        [row("082740", "ANALISI MATEMATICA 1"), row("082746", "FONDAMENTI DI INFORMATICA"),
         row("052496", "ALGORITHMS AND PARALLEL COMPUTING", year: "2"), row("099999", "ANALISI MATEMATICA 2", year: "2")]
    }

    @Test("A code in the course's title or idnumber finds its plan teaching")
    func byCode() {
        #expect(PlanCourseMatch.match(codes: ["082746"], name: "Qualcosa", in: plan)?.teaching.code == "082746")
    }

    @Test("Without a code, the same name finds it, accents and case aside")
    func byName() {
        #expect(PlanCourseMatch.match(codes: [], name: "Analisi Matematica 1", in: plan)?.teaching.code == "082740")
        #expect(PlanCourseMatch.match(codes: [], name: "Algorithms and Parallel Computing [2026-27]", in: plan)?.teaching.code == "052496")
    }

    @Test("A name contained in two teachings is not guessed")
    func ambiguous() {
        #expect(PlanCourseMatch.match(codes: [], name: "Analisi Matematica", in: plan) == nil)
        #expect(PlanCourseMatch.match(codes: [], name: "Storia", in: plan) == nil)
    }

    private func module(_ from: String?, _ to: String?, _ id: String?) -> ManifestoModule {
        ManifestoModule(code: "082740", name: "ANALISI", teachers: [ManifestoTeacher(name: "T\(from ?? "")", kDoc: nil)],
                        credits: nil, period: nil, language: nil, scaglioneFrom: from, scaglioneTo: to, syllabusID: id)
    }

    @Test("The scheda is the chosen bracket's, else the one the surname falls in, else the first")
    func scheda() {
        let modules = [module("A", "CON", "1"), module("CON", "RET", "2"), module("RET", "ZZZZ", "3")]
        #expect(SyllabusPicker.module(in: modules, bracket: nil, surname: "Rossi")?.syllabusID == "3")
        #expect(SyllabusPicker.module(in: modules, bracket: BracketChoice(from: "CON ", to: "RET", teachers: []),
                                      surname: "Rossi")?.syllabusID == "2")
        #expect(SyllabusPicker.module(in: modules, bracket: nil, surname: nil)?.syllabusID == "1")
        #expect(SyllabusPicker.module(in: [module(nil, nil, nil)], bracket: nil, surname: "Rossi") == nil)
    }

    @Test("A programme is kept per matricola, never shared between careers")
    func store() throws {
        let defaults = try #require(UserDefaults(suiteName: "study-programme-tests"))
        defaults.removePersistentDomain(forName: "study-programme-tests")
        let store = StudyProgrammeStore(defaults: defaults)
        var programme = StudyProgramme(selection: CatalogueSelection(year: "2026", campus: "MI", school: "225",
                                                                     degree: "531", plan: "IT1"),
                                       degreeLabel: "Ingegneria Informatica (531)", planLabel: "IT1", isConfirmed: false)
        programme.brackets["082740"] = BracketChoice(from: "CON", to: "FOT", teachers: ["De Martino"])
        store.save(programme, for: "986617")
        #expect(store.programme(for: "986617") == programme)
        #expect(store.programme(for: "337940") == nil)
        store.save(nil, for: "986617")
        #expect(store.programme(for: "986617") == nil)
    }

    @Test("The plan is asked for in the course's own academic year")
    func year() {
        let programme = StudyProgramme(selection: CatalogueSelection(year: "2026", campus: "MI", school: "225",
                                                                     degree: "531", plan: "IT1"),
                                       degreeLabel: "", planLabel: "", isConfirmed: true)
        #expect(programme.selection(forYear: "2025").year == "2025")
        #expect(programme.selection(forYear: nil).year == "2026")
        #expect(programme.selection(forYear: "2025").plan == "IT1")
    }
}

/// Each career keeps its own programme, chosen by the student; courses are
/// looked up in the one in use first, then in the others.
@Suite("Programmes per career")
struct CareerProgrammesTests {
    private func programme(_ degree: String, _ plan: String, confirmed: Bool = true) -> StudyProgramme {
        StudyProgramme(selection: CatalogueSelection(year: "2026", campus: "ALL_SEDI", school: "225", degree: degree, plan: plan),
                       degreeLabel: degree, planLabel: plan, isConfirmed: confirmed)
    }

    @Test("The careers listed, the one in use first, each with its programme or none")
    func rows() throws {
        let defaults = try #require(UserDefaults(suiteName: "career-programmes-tests"))
        defaults.removePersistentDomain(forName: "career-programmes-tests")
        let store = StudyProgrammeStore(defaults: defaults)
        store.save(programme("531", "I3I"), for: "986617")
        let rows = CareerProgrammes.rows(current: "986617", careers: ["337940", "986617"], store: store)
        #expect(rows.map(\.matricola) == ["986617", "337940"])
        #expect(rows.map { $0.programme?.selection.degree } == ["531", nil])
    }

    @Test("Other careers are searched only with a programme the student confirmed")
    func others() throws {
        let defaults = try #require(UserDefaults(suiteName: "career-programmes-tests-2"))
        defaults.removePersistentDomain(forName: "career-programmes-tests-2")
        let store = StudyProgrammeStore(defaults: defaults)
        store.save(programme("542", "T2A"), for: "337940")
        store.save(programme("999", "X", confirmed: false), for: "111111")
        let others = CareerProgrammes.others(current: "986617", careers: ["986617", "337940", "111111"], store: store)
        #expect(others.map(\.selection.degree) == ["542"])
    }
}

@Suite("Matricole seen")
struct SeenMatricoleTests {
    @Test("Every matricola signed in with is remembered per person, in order, once")
    func seen() throws {
        let defaults = try #require(UserDefaults(suiteName: "seen-matricole-tests"))
        defaults.removePersistentDomain(forName: "seen-matricole-tests")
        let store = StudyProgrammeStore(defaults: defaults)
        store.remember("986617", person: "10712345")
        store.remember("337940", person: "10712345")
        store.remember("986617", person: "10712345")
        store.remember("111111", person: "99999999")
        #expect(store.seenMatricole(person: "10712345") == ["986617", "337940"])
        #expect(store.seenMatricole(person: "99999999") == ["111111"])
    }
}

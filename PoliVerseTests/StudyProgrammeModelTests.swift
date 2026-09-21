import Foundation
import Testing
@testable import PoliVerse

/// The largest module in the app, and until now the only one of its size with
/// no test at all.
///
/// It held ``ManifestiModel``, ``CareerModel`` and ``CareersModel`` — three
/// concrete stateful models, one of which builds its own `URLSession` against
/// an HTML-only site and another of which wants an account, a feed and a
/// queue. Standing it up meant standing up all of that. It now takes
/// ``ManifestoReading``, ``StudentRecord``, ``Enrolments`` and ``Account``,
/// which a test supplies in a dozen lines.
@Suite("Study programme")
@MainActor
struct StudyProgrammeModelTests {
    /// Answers nothing. Every test here is about what the model does with the
    /// student's own records, not about the catalogue.
    private final class SilentCatalogue: ManifestoReading {
        func cataloguePage(_ selection: CatalogueSelection?,
                           language: PoliMiLanguage) async -> CataloguePage? { nil }
        func locateDegree(choosing choose: ([CatalogueOption]) -> CatalogueOption?) async -> CataloguePage? { nil }
        func locateDegree(named degree: String, kind: String?) async -> CataloguePage? { nil }
        func offeringRows(teachingCode: String, yearCode: String) async -> [ManifestoTeaching]? { nil }
        func detail(for teaching: ManifestoTeaching) async -> ManifestoDetail? { nil }
        func brackets(for teaching: ManifestoTeaching) async -> [BracketChoice] { [] }
        func syllabusPick(teachingCode: String, surname: String?, degreeName: String?,
                          yearCode: String?) async -> SyllabusPicker.Pick? { nil }
    }

    private final class StubRecord: StudentRecord {
        var libretto: [LibrettoExam] = []
        var planHeader: StudyPlanHeader?
        private(set) var loads = 0
        func load(force: Bool) async { loads += 1 }
    }

    private final class StubEnrolments: Enrolments {
        var matricole: [String] = []
        var current: Career?
    }

    /// Defaults of its own: the store keys what it remembers by person, and
    /// two tests must not see each other's.
    private func store() -> StudyProgrammeStore {
        StudyProgrammeStore(defaults: UserDefaults(suiteName: "plan-\(UUID().uuidString)")!)
    }

    private func model(matricola: String? = "111", personCode: String? = "p1",
                       record: StubRecord = StubRecord(),
                       enrolments: StubEnrolments? = nil,
                       store: StudyProgrammeStore? = nil) -> StudyProgrammeModel {
        StudyProgrammeModel(
            manifesti: SilentCatalogue(),
            account: StubAccount(matricola: matricola, personCode: personCode),
            career: record,
            careers: enrolments,
            store: store ?? self.store())
    }

    /// The point of the whole exercise: this line could not be written before.
    @Test("The model can be built without a session, a network or a catalogue")
    func isConstructible() {
        let plan = model()
        #expect(plan.programme == nil)
        #expect(plan.isLocating == false)
    }

    /// Sample data is not this student's, so nothing may be filed under their
    /// matricola — the store is keyed by it, and the rows lead with it.
    @Test("In sample mode there is no matricola to key anything by")
    func sampleModeHasNoMatricola() {
        let plan = StudyProgrammeModel(
            manifesti: SilentCatalogue(),
            account: StubAccount(matricola: "111", isSample: true),
            career: StubRecord(), careers: nil, store: store())

        // Nothing claims to be the career in use, because there is none.
        #expect(plan.careerRows.isEmpty)
    }

    /// A person has a matricola per enrolment. The rows are every career the
    /// app knows of — those listed by the service and those it has been
    /// signed in with before — without repeating one.
    @Test("Career rows are the listed and the remembered, each once")
    func careerRowsAreDeduplicated() {
        let enrolments = StubEnrolments()
        enrolments.matricole = ["111", "222"]
        let plan = model(enrolments: enrolments)

        let matricole = plan.careerRows.map(\.matricola)
        #expect(Set(matricole) == ["111", "222"])
        #expect(matricole.count == 2)
    }

    /// The enrolment in use leads, because it is the one the student is
    /// looking at.
    @Test("The career in use comes first")
    func currentCareerLeads() throws {
        let enrolments = StubEnrolments()
        enrolments.matricole = ["222", "111"]
        let plan = model(matricola: "111", enrolments: enrolments)

        // Listed second by the service, first here: the rows lead with the
        // enrolment in use.
        let first = try #require(plan.careerRows.first)
        #expect(first.matricola == "111")
        #expect(plan.careerRows.map(\.matricola) == ["111", "222"])
    }

    /// Signed out there is no person to key the store by and no enrolment in
    /// use, so the rows are exactly what the service listed — nothing is
    /// promoted to the front and nothing is remembered from before.
    @Test("Signed out, the rows are just what was listed")
    func signedOutListsOnlyTheService() {
        let enrolments = StubEnrolments()
        enrolments.matricole = ["111", "222"]
        let plan = model(matricola: nil, personCode: nil, enrolments: enrolments)

        #expect(plan.careerRows.map(\.matricola) == ["111", "222"])
    }
}

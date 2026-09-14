import Foundation
import Observation
import OSLog

/// The student's degree course and plan, and everything read against them.
///
/// One programme per matricola. Located once from the career's degree name
/// when nothing has been chosen — as a guess the student is asked to confirm —
/// and set outright when they pick it in the manifesto.
@Observable
final class StudyProgrammeService {
    private(set) var programme: StudyProgramme?
    /// Teaching codes of every plan page read so far, for telling WeBeep
    /// courses of the plan apart from the rest.
    private(set) var planCodes: Set<String> = []
    private(set) var isLocating = false

    private let manifesti: ManifestiService
    private let session: Session
    private let career: CareerService
    private let store: StudyProgrammeStore
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "manifesti")

    @ObservationIgnored private var loadedFor: String?
    @ObservationIgnored private var plans: [CatalogueSelection: [PlanTeaching]] = [:]
    @ObservationIgnored private var locateAttempted: Set<String> = []

    init(manifesti: ManifestiService, session: Session, career: CareerService,
         store: StudyProgrammeStore = StudyProgrammeStore()) {
        self.manifesti = manifesti
        self.session = session
        self.career = career
        self.store = store
    }

    private var matricola: String? {
        session.useMockData ? nil : session.student?.matricola
    }

    /// Brings the programme in line with the career in use, locating one when
    /// there is none. Cheap once done; call from any screen that needs it.
    func prepare() async {
        guard let matricola else { return }
        if loadedFor != matricola {
            loadedFor = matricola
            programme = store.programme(for: matricola)
            plans = [:]
            planCodes = []
        }
        guard programme == nil, locateAttempted.insert(matricola).inserted else { return }
        await career.load()
        guard let degree = career.planHeader?.course, !degree.isEmpty else { return }
        isLocating = true
        defer { isLocating = false }
        guard let page = await manifesti.locateDegree(named: degree), matricola == self.matricola else { return }
        set(page, confirmed: false)
        log.notice("study programme located from the career: \(page.selection.map { "\($0.degree)/\($0.plan)" } ?? "-", privacy: .public)")
    }

    /// The programme as a manifesto page shows it.
    func set(_ page: CataloguePage, confirmed: Bool) {
        guard let matricola, let selection = page.selection else { return }
        let label = { (field: CatalogueField) in
            page.level(field)?.options.first { $0.value == selection[field] }?.label ?? selection[field]
        }
        var updated = StudyProgramme(selection: selection, degreeLabel: label(.degree), planLabel: label(.plan),
                                     isConfirmed: confirmed)
        // Same plan: the brackets chosen for its teachings still apply.
        if programme?.selection.degree == selection.degree, programme?.selection.plan == selection.plan {
            updated.brackets = programme?.brackets ?? [:]
        }
        save(updated)
        plans = [:]
        planCodes = []
    }

    func confirm() {
        guard var current = programme else { return }
        current.isConfirmed = true
        save(current)
    }

    func choose(bracket: BracketChoice?, forTeaching code: String) {
        guard var current = programme else { return }
        current.brackets[code] = bracket
        save(current)
    }

    private func save(_ value: StudyProgramme) {
        programme = value
        if let matricola { store.save(value, for: matricola) }
    }

    // MARK: - Plan pages

    /// The plan's teachings in an academic year: the manifesto of the year the
    /// course was taken, which is where its lecturers and schede are.
    func plan(forYear year: String?) async -> [PlanTeaching] {
        guard let programme else { return [] }
        let selection = programme.selection(forYear: year)
        if let cached = plans[selection] { return cached }
        guard let page = await manifesti.cataloguePage(selection) else { return [] }
        // The service settles a plan that does not exist that year onto
        // another one: only its own plan counts.
        guard page.selection?.degree == selection.degree, page.selection?.plan == selection.plan else {
            plans[selection] = []
            return []
        }
        plans[selection] = page.teachings
        planCodes.formUnion(page.teachings.map(\.teaching.code))
        return page.teachings
    }

    /// Which plan teaching a course is, in its own academic year.
    func planTeaching(codes: [String], name: String, year: String?) async -> PlanTeaching? {
        await prepare()
        return PlanCourseMatch.match(codes: codes, name: name, in: await plan(forYear: year))
    }

    // MARK: - Scheda

    /// The scheda of one of the student's teachings: the row of their own plan,
    /// in the bracket they chose or their surname gives. Falls back to the
    /// catalogue-wide search when there is no programme or the plan does not
    /// list the teaching.
    func pick(teachingCode: String?, name: String, yearCode: String?) async -> SyllabusPicker.Pick? {
        let surname = session.student?.lastName
        if let row = await planTeaching(codes: [teachingCode].compactMap { $0 }, name: name, year: yearCode),
           let detail = await manifesti.detail(for: row.teaching),
           let module = SyllabusPicker.module(in: detail.modules, bracket: programme?.brackets[row.teaching.code],
                                              surname: surname) {
            return SyllabusPicker.Pick(degreeCourse: programme?.degreeLabel ?? detail.degreeCourse,
                                       module: module, matchesDegree: true)
        }
        guard let teachingCode else { return nil }
        return await manifesti.syllabusPick(teachingCode: teachingCode, surname: surname,
                                            degreeName: career.planHeader?.course, yearCode: yearCode)
    }

    func prefetch(teachingCode: String?, name: String, yearCode: String?) {
        Task(priority: .utility) {
            if let id = await pick(teachingCode: teachingCode, name: name, yearCode: yearCode)?.module.syllabusID {
                _ = await manifesti.syllabus(for: id)
            }
        }
    }

    /// The brackets of the plan teaching a course is, for choosing one.
    func brackets(teachingCode: String?, name: String, yearCode: String?) async -> (PlanTeaching, [BracketChoice])? {
        guard let row = await planTeaching(codes: [teachingCode].compactMap { $0 }, name: name, year: yearCode)
        else { return nil }
        return (row, await manifesti.brackets(for: row.teaching))
    }

    // MARK: - Courses

    /// Teaching codes for courses that have none — WeBeep pages whose title
    /// carries only a name — found in the plan of each course's year.
    func codes(for courses: [Course]) async -> [String: String] {
        await prepare()
        guard programme != nil else { return [:] }
        var found: [String: String] = [:]
        for course in courses where course.teachingCode == nil {
            guard !Task.isCancelled else { break }
            let plan = await plan(forYear: course.academicYearStart)
            if let row = PlanCourseMatch.match(codes: [], name: course.name, in: plan) {
                found[course.id] = row.teaching.code
            }
        }
        return found
    }
}

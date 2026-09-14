import Foundation
import Observation
import OSLog

/// The student's degree course and plan, and everything read against them.
///
/// One programme per matricola. Found from the student's own records when
/// nothing has been chosen — the plan header's codes if it has them, else the
/// degree course by name and level, with each of its plans scored against the
/// libretto — and set outright when they pick it in the manifesto.
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
    private let careers: CareersService?
    private let store: StudyProgrammeStore
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "manifesti")

    /// The student's course codes per academic year, from the course list —
    /// what tells which plan a course outside the programme belongs to.
    @ObservationIgnored var enrolledCodes: [String: Set<String>] = [:]
    /// Plans followed in a year besides the programme, by year.
    @ObservationIgnored private var others: [String: StudyProgramme] = [:]
    @ObservationIgnored private var othersAttempted: Set<String> = []
    @ObservationIgnored private var loadedFor: String?
    @ObservationIgnored private var plans: [String: [PlanTeaching]] = [:]
    @ObservationIgnored private var locateAttempted: Set<String> = []

    /// A week: a plan page changes when the manifesto does, once a year.
    static let planLifetime: TimeInterval = 7 * 86400
    /// Plans of one degree course scored against the libretto, at most.
    static let plansScored = 6

    init(manifesti: ManifestiService, session: Session, career: CareerService, careers: CareersService? = nil,
         store: StudyProgrammeStore = StudyProgrammeStore()) {
        self.manifesti = manifesti
        self.session = session
        self.career = career
        self.careers = careers
        self.store = store
    }

    private var matricola: String? {
        session.useMockData ? nil : session.student?.matricola
    }

    /// The libretto by teaching name: it carries no teaching codes.
    private var librettoKeys: Set<String> { ProgrammeInference.keys(of: career.libretto) }

    // MARK: - The programme

    /// Brings the programme in line with the career in use, finding one when
    /// there is none and checking the one there is. Cheap once done.
    func prepare() async {
        guard let matricola else { return }
        if loadedFor != matricola {
            loadedFor = matricola
            programme = store.programme(for: matricola)
            others = [:]
            othersAttempted = []
            plans = [:]
            planCodes = []
        }
        guard locateAttempted.insert(matricola).inserted else { return }
        await career.load()
        if programme == nil {
            await locate(for: matricola)
        } else {
            await review()
        }
    }

    private func locate(for matricola: String) async {
        isLocating = true
        defer { isLocating = false }
        let header = career.planHeader
        // The plan header's level ("Laurea di primo livello"); the careers
        // list only says "Studente".
        let kind = header?.level ?? careers?.current?.kind

        // 1. The header's own codes, when the service sends them.
        var page: CataloguePage?
        if let code = header?.degreeCode {
            page = await manifesti.locateDegree { options in options.first { $0.value == code } }
        }
        // 2. The degree course by name, the career's level deciding between
        //    a bachelor's and a master's of the same name.
        if page == nil, let name = header?.course, !name.isEmpty {
            page = await manifesti.locateDegree(named: name, kind: kind)
        }
        if page == nil, let name = header?.englishCourse, !name.isEmpty {
            page = await manifesti.locateDegree(named: name, kind: kind)
        }
        // In the plan's own year: the header says which manifesto it follows.
        if let year = header?.yearCode, let current = page?.selection, current.year != year,
           let inYear = await manifesti.cataloguePage(current.setting(.year, to: year)),
           inYear.selection?.degree == current.degree {
            page = inYear
        }
        guard var located = page, let base = located.selection, matricola == self.matricola else { return }
        if let plan = header?.planCode, located.level(.plan)?.options.contains(where: { $0.value == plan }) == true,
           let exact = await manifesti.cataloguePage(base.setting(.plan, to: plan)) {
            set(exact, confirmed: true)
            return
        }

        // 3. Every plan of that degree course against the libretto.
        var confirmed = false
        let libretto = librettoKeys
        let planOptions = (located.level(.plan)?.options ?? []).filter { $0.value != "***" }.prefix(Self.plansScored)
        if !libretto.isEmpty, planOptions.count > 1 {
            var candidates: [(CatalogueSelection, [String])] = []
            var pages: [CatalogueSelection: CataloguePage] = [:]
            for option in planOptions {
                let selection = base.setting(.plan, to: option.value)
                guard let candidate = await manifesti.cataloguePage(selection), let settled = candidate.selection else { continue }
                pages[settled] = candidate
                candidates.append((settled, ProgrammeInference.keys(of: candidate.teachings)))
            }
            if let best = ProgrammeInference.best(libretto: libretto, candidates: candidates) {
                // Plans sharing as many teachings: the career's track —
                // "Informatica" — names the one among them.
                var answer = best.selection
                if best.tied.count > 1, let track = header?.track,
                   let byTrack = best.tied.first(where: { selection in
                       let label = planOptions.first { $0.value == selection.plan }?.label
                       return DegreeCourseMatch.matches(label, plan: track)
                   }) {
                    answer = byTrack
                    confirmed = best.overlap >= 3
                } else {
                    confirmed = best.isConfident
                }
                if let chosen = pages[answer] { located = chosen }
            }
        } else if !libretto.isEmpty {
            confirmed = ProgrammeInference.best(libretto: libretto, candidates: [(base, ProgrammeInference.keys(of: located.teachings))])?
                .isConfident ?? false
        }
        guard matricola == self.matricola else { return }
        set(located, confirmed: confirmed)
        log.notice("study programme found: \(located.selection.map { "\($0.degree)/\($0.plan)" } ?? "-", privacy: .public), confirmed \(confirmed, privacy: .public)")
    }

    /// Asks again when the records stopped fitting: the plan is gone from this
    /// year's manifesto, or the libretto shares nothing with it any more.
    private func review() async {
        guard let current = programme, current.isConfirmed else { return }
        let year = AcademicYear.recent().first?.code ?? current.selection.year
        let plan = await plan(forYear: year)
        let gone = plan.isEmpty && plans[key(current.selection(forYear: year))] != nil
        let misfit = !ProgrammeInference.stillFits(libretto: librettoKeys, plan: Set(ProgrammeInference.keys(of: plan)))
        guard gone || misfit, var updated = programme else { return }
        updated.isConfirmed = false
        updated.needsReview = true
        save(updated)
        log.notice("study programme needs review: gone \(gone, privacy: .public), misfit \(misfit, privacy: .public)")
    }

    /// The programme as a manifesto page shows it.
    func set(_ page: CataloguePage, confirmed: Bool) {
        guard matricola != nil, let selection = page.selection else { return }
        let label = { (field: CatalogueField) in
            page.level(field)?.options.first { $0.value == selection[field] }?.label ?? selection[field]
        }
        var updated = StudyProgramme(selection: selection, degreeLabel: label(.degree), planLabel: label(.plan),
                                     isConfirmed: confirmed)
        // Same plan: what was decided about its teachings still applies.
        if let previous = programme, previous.selection.degree == selection.degree, previous.selection.plan == selection.plan {
            updated.brackets = previous.brackets
            updated.inferredBrackets = previous.inferredBrackets
            updated.links = previous.links
        }
        save(updated)
        plans = [:]
        planCodes = []
    }

    func confirm() {
        guard var current = programme else { return }
        current.isConfirmed = true
        current.needsReview = false
        save(current)
    }

    func choose(bracket: BracketChoice?, forTeaching code: String) {
        guard var current = programme else { return }
        current.brackets[code] = bracket
        save(current)
    }

    /// Links a course to a teaching of the plan by hand; nil removes the link.
    func link(courseID: String, to code: String?) {
        guard var current = programme else { return }
        current.links[courseID] = code
        save(current)
    }

    private func save(_ value: StudyProgramme) {
        programme = value
        if let matricola { store.save(value, for: matricola) }
    }

    // MARK: - Plan pages

    private func key(_ selection: CatalogueSelection, language: PoliMiLanguage = .current) -> String {
        ["plan", selection.year, selection.school, selection.degree, selection.plan, language.rawValue]
            .joined(separator: "-").replacingOccurrences(of: "*", with: "x")
    }

    /// The plan's teachings in an academic year: the manifesto of the year the
    /// course was taken, which is where its lecturers and schede are. Kept on
    /// disk for a week, so the course list and the scheda open without it.
    func plan(forYear year: String?, language: PoliMiLanguage = .current) async -> [PlanTeaching] {
        guard let programme else { return [] }
        return await plan(of: programme, year: year, language: language)
    }

    private func plan(of programme: StudyProgramme, year: String?, language: PoliMiLanguage = .current) async -> [PlanTeaching] {
        let selection = programme.selection(forYear: year)
        let name = key(selection, language: language)
        if let cached = plans[name] { return cached }
        if let stored = await Self.stored(name), stored.isFresh(within: Self.planLifetime) {
            remember(stored.value, as: name, language: language)
            return stored.value
        }
        guard let page = await manifesti.cataloguePage(selection, language: language) else {
            // Offline: last week's plan beats none.
            return await Self.stored(name)?.value ?? []
        }
        // The service settles a plan that does not exist that year onto
        // another one: only its own plan counts.
        let teachings = page.selection?.degree == selection.degree && page.selection?.plan == selection.plan
            ? page.teachings : []
        remember(teachings, as: name, language: language)
        await Self.store(teachings, as: name)
        return teachings
    }

    private func remember(_ teachings: [PlanTeaching], as name: String, language: PoliMiLanguage) {
        plans[name] = teachings
        if language == .current { planCodes.formUnion(teachings.map(\.teaching.code)) }
    }

    @concurrent
    private static func stored(_ name: String) async -> DiskCache.Entry<[PlanTeaching]>? {
        DiskCache.load([PlanTeaching].self, as: name)
    }

    @concurrent
    private static func store(_ teachings: [PlanTeaching], as name: String) async {
        DiskCache.save(teachings, as: name)
    }

    /// Which plan teaching a course is, in its own academic year: a link made
    /// by hand, else code, else name — in the app's language, then in the
    /// other one, since WeBeep titles and the manifesto do not always agree.
    func planTeaching(codes: [String], name: String, year: String?, courseID: String? = nil) async -> PlanTeaching? {
        await prepare()
        let plan = await plan(forYear: year)
        if let courseID, let linked = programme?.links[courseID], let row = plan.first(where: { $0.teaching.code == linked }) {
            return row
        }
        if let row = PlanCourseMatch.match(codes: codes, name: name, in: plan) { return row }
        let other: PoliMiLanguage = PoliMiLanguage.current == .english ? .italian : .english
        if !plan.isEmpty,
           let translated = PlanCourseMatch.match(codes: [], name: name, in: await self.plan(forYear: year, language: other)),
           let row = plan.first(where: { $0.teaching.code == translated.teaching.code }) {
            return row
        }
        // Not in the programme: the plan the student's other courses of that
        // year point to — a master's course seen from the bachelor's career.
        return await otherPlanTeaching(codes: codes, name: name, year: year)?.row
    }

    /// The row, and the plan it is in, for a course outside the programme.
    ///
    /// From catalogue searches: one for the course and one for each of the
    /// student's other courses that year, together. The degree course offering
    /// most of them is theirs; when two tie and both give the student's surname
    /// the same lecturers, either is right.
    private func otherPlanTeaching(codes: [String], name: String, year: String?)
        async -> (row: PlanTeaching, programme: StudyProgramme)? {
        guard let matricola, let year = year ?? programme?.selection.year, let code = codes.first else { return nil }
        if others[year] == nil, let stored = store.otherProgramme(for: matricola, year: year) { others[year] = stored }
        let manifesti = self.manifesti

        // Known already for that year: whether it offers this course is one
        // search, kept on disk.
        if let known = others[year], let rows = await manifesti.offeringRows(teachingCode: code, yearCode: year),
           let row = rows.first(where: { $0.courseCode == known.selection.degree && $0.planCode == known.selection.plan })
               ?? rows.first(where: { $0.courseCode == known.selection.degree }) {
            return (PlanTeaching(teaching: row, yearOfCourse: nil, credits: nil, group: nil, hasSections: false), known)
        }
        guard othersAttempted.insert("\(year)/\(code)").inserted else { return nil }

        let asked = [code] + (enrolledCodes[year] ?? []).subtracting([code]).sorted().prefix(8)
        let offerings = await withTaskGroup(of: (String, [ManifestoTeaching]?).self) { group in
            for each in asked {
                group.addTask { (each, await manifesti.offeringRows(teachingCode: each, yearCode: year)) }
            }
            var found: [String: [ManifestoTeaching]] = [:]
            for await (each, rows) in group { if let rows { found[each] = rows } }
            return found
        }
        var tied = SearchInference.tiedRows(for: code, offerings: offerings)
        if tied.count > 1 {
            let surname = session.student?.lastName
            let lecturers = await withTaskGroup(of: [String].self) { group in
                for row in tied {
                    group.addTask {
                        let modules = await manifesti.detail(for: row)?.modules ?? []
                        return SyllabusPicker.module(in: modules, bracket: nil, surname: surname)?.teachers.map(\.name) ?? []
                    }
                }
                var found: Set<[String]> = []
                for await names in group { found.insert(names) }
                return found
            }
            if lecturers.count == 1, lecturers.first?.isEmpty == false { tied = [tied[0]] }
        }
        guard tied.count == 1, let row = tied.first else {
            log.notice("no degree course stands out for \(code, privacy: .public) in \(year, privacy: .public): \(tied.map(\.courseCode), privacy: .public)")
            return nil
        }
        let schools = await manifesti.cataloguePage(nil)?.level(.school)?.options ?? []
        let school = row.degreeCourse.flatMap { SearchInference.school(heading: $0, in: schools) } ?? "-1"
        let found = StudyProgramme(
            selection: CatalogueSelection(year: year, campus: "ALL_SEDI", school: school, degree: row.courseCode,
                                          plan: row.planCode ?? "***"),
            degreeLabel: row.degreeCourse ?? row.courseCode, planLabel: row.planCode ?? "", isConfirmed: false)
        others[year] = found
        store.saveOther(found, for: matricola, year: year)
        log.notice("course \(code, privacy: .public) read in \(row.courseCode, privacy: .public)/\(row.planCode ?? "-", privacy: .public) for \(year, privacy: .public), from \(offerings.count, privacy: .public) searches")
        return (PlanTeaching(teaching: row, yearOfCourse: nil, credits: nil, group: nil, hasSections: false), found)
    }

    // MARK: - Scheda

    /// The scheda of one of the student's teachings: the row of their own plan,
    /// in the bracket they chose, the one their WeBeep page shows, or their
    /// surname's. Falls back to the catalogue-wide search when there is no
    /// programme or the plan does not list the teaching.
    func pick(teachingCode: String?, name: String, yearCode: String?, courseID: String? = nil) async -> SyllabusPicker.Pick? {
        let surname = session.student?.lastName
        if let row = await planTeaching(codes: [teachingCode].compactMap { $0 }, name: name, year: yearCode, courseID: courseID),
           let detail = await manifesti.detail(for: row.teaching),
           let module = SyllabusPicker.module(in: detail.modules, bracket: programme?.bracket(for: row.teaching.code),
                                              surname: surname) {
            // The row's own degree course: the programme's, or the other plan
            // the course was found in.
            return SyllabusPicker.Pick(degreeCourse: detail.degreeCourse ?? programme?.degreeLabel,
                                       module: module, matchesDegree: true)
        }
        guard let teachingCode else { return nil }
        return await manifesti.syllabusPick(teachingCode: teachingCode, surname: surname,
                                            degreeName: career.planHeader?.course, yearCode: yearCode)
    }

    func prefetch(teachingCode: String?, name: String, yearCode: String?, courseID: String? = nil) {
        Task(priority: .utility) {
            if let id = await pick(teachingCode: teachingCode, name: name, yearCode: yearCode, courseID: courseID)?
                .module.syllabusID {
                _ = await manifesti.syllabus(for: id)
            }
        }
    }

    /// The brackets of the plan teaching a course is, for choosing one.
    func brackets(teachingCode: String?, name: String, yearCode: String?, courseID: String? = nil)
        async -> (PlanTeaching, [BracketChoice])? {
        guard let row = await planTeaching(codes: [teachingCode].compactMap { $0 }, name: name, year: yearCode,
                                           courseID: courseID) else { return nil }
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
            if let row = await planTeaching(codes: [], name: course.name, year: course.academicYearStart, courseID: course.id) {
                found[course.id] = row.teaching.code
            }
        }
        return found
    }

    /// Brackets from the lecturers of the student's WeBeep pages: the page of
    /// De Martino's Analisi 1 means the CON–FOT bracket, whatever the surname.
    /// Only this academic year's courses, and never over a choice made by hand.
    func inferBrackets(courses: [Course], contacts: [Int: [String]]) async {
        guard programme != nil else { return }
        let year = AcademicYear.recent().first?.code
        var inferred: [String: BracketChoice] = [:]
        for course in courses where course.academicYearStart == year {
            guard !Task.isCancelled, let id = course.moodleID, let people = contacts[id], !people.isEmpty,
                  let row = await planTeaching(codes: [course.teachingCode].compactMap { $0 }, name: course.name,
                                               year: year, courseID: course.id),
                  programme?.brackets[row.teaching.code] == nil else { continue }
            let brackets = await manifesti.brackets(for: row.teaching)
            if let bracket = BracketInference.bracket(contacts: people, brackets: brackets) {
                inferred[row.teaching.code] = bracket
            }
        }
        guard var current = programme, current.inferredBrackets != inferred, !inferred.isEmpty else { return }
        current.inferredBrackets.merge(inferred) { _, new in new }
        save(current)
    }
}

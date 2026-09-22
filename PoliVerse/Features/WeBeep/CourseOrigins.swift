import SwiftUI

/// Where each course on a list comes from — the student's plan, another
/// career's, or joined by choice — for the lists that filter by it: WeBeep's
/// and Corsi's.
struct CourseOrigins {
    /// Which courses a list shows.
    enum Filter: Hashable, CaseIterable {
        /// Everything; the current career's plan; another career's; or joined by choice.
        case all, plan, otherCareer, byChoice

        /// The filter's name on screen.
        var title: LocalizedStringKey {
            switch self {
            case .all: "Tutti"
            case .plan: "Del piano"
            case .otherCareer: "Altra carriera"
            case .byChoice: "Iscrizione libera"
            }
        }
    }

    /// The careers' study plans, the current one first, which a course is classified against.
    let plans: [EnrolmentOrigin.Plan]
    /// The classifications the student corrected, by ``Course/id``.
    let overrides: [String: EnrolmentOrigin.Override]
    /// Supplies each course's Moodle row and whether its page takes self-enrolment.
    let weBeep: WeBeepModel

    /// The current career's plan — the libretto and the plan pages read for
    /// it, so a course of the plan counts even before the libretto lists it —
    /// then the other careers'.
    @MainActor
    init(student: Student?, career: CareerModel, programmes: StudyProgrammeModel, otherPlans: [EnrolmentOrigin.Plan],
         overrides: [String: EnrolmentOrigin.Override], weBeep: WeBeepModel) {
        let current = EnrolmentOrigin.Plan(matricola: student?.matricola ?? "", isCurrent: true, libretto: career.libretto)
        plans = [EnrolmentOrigin.Plan(matricola: current.matricola, isCurrent: true,
                                      codes: current.codes.union(programmes.planCodes),
                                      names: Set(career.libretto.map(\.name)))] + otherPlans
        self.overrides = overrides
        self.weBeep = weBeep
    }

    /// Why a course is on the student's list.
    ///
    /// - Parameter course: The course to classify.
    /// - Returns: Its origin, the student's own correction included.
    @MainActor
    func origin(of course: Course) -> EnrolmentOrigin {
        let moodle = course.moodleID.flatMap(weBeep.moodleCourse(id:))
        return EnrolmentOrigin.classify(
            codes: EnrolmentOrigin.codes(in: [course.teachingCode, moodle?.idnumber, moodle?.shortname]),
            name: course.name, plans: plans, override: overrides[course.id],
            selfEnrolmentOpen: course.moodleID.flatMap { weBeep.selfEnrolment[$0] })
    }

    /// The courses a filter leaves.
    ///
    /// - Parameters:
    ///   - list: The courses to filter.
    ///   - filter: What to show.
    /// - Returns: The matching courses, in the order given.
    @MainActor
    func filter(_ list: [Course], by filter: Filter) -> [Course] {
        guard filter != .all else { return list }
        return list.filter { course in
            switch (origin(of: course), filter) {
            case (.currentPlan, .plan), (.otherCareer, .otherCareer), (.outsidePlan, .byChoice), (.selfEnrolled, .byChoice): true
            default: false
            }
        }
    }

    /// A line saying where a course comes from, left out for the plan's own.
    static func label(_ origin: EnrolmentOrigin) -> String? {
        switch origin {
        case .currentPlan, .unknown: nil
        case .otherCareer(let matricola): String(localized: "Piano della matricola \(matricola)")
        case .outsidePlan: String(localized: "Fuori dal piano di studi")
        case .selfEnrolled: String(localized: "Probabile iscrizione libera")
        }
    }

    /// Loads what the origins are read from, in the order each step needs the
    /// last: courses and careers, the other careers' cached plans, this
    /// career's plans for every year listed, the brackets, and last how the
    /// pages outside every plan take enrolments.
    ///
    /// - Returns: the other careers' plans, read from their caches.
    @MainActor
    static func load(courses: CourseModel, careers: CareersModel, career: CareerModel,
                     programmes: StudyProgrammeModel, weBeep: WeBeepModel, student: Student?,
                     otherPlans: (([EnrolmentOrigin.Plan]) -> Void)) async {
        await courses.load()
        await careers.load()
        let current = student?.matricola
        let others = careers.careers.filter { $0.matricola != current }.compactMap { other in
            CareerModel.cachedLibretto(account: other.matricola).map {
                EnrolmentOrigin.Plan(matricola: other.matricola, isCurrent: false, libretto: $0)
            }
        }
        otherPlans(others)
        await career.load()
        // The plan of every year the list covers, so its courses read
        // as "del piano" by the plan itself, not only by the libretto.
        await programmes.prepare()
        for year in Set(courses.courses.compactMap(\.academicYearStart)) {
            _ = await programmes.plan(forYear: year)
        }
        // This year's lecturers say which bracket each course is followed in.
        let thisYear = AcademicYear.recent().first?.code
        let thisYearCourses = courses.courses.filter { $0.academicYearStart == thisYear }
        await weBeep.loadContacts(for: thisYearCourses.compactMap(\.moodleID))
        await programmes.inferBrackets(courses: thisYearCourses, contacts: weBeep.contacts)
        // Only pages outside every plan need asking how they enrol.
        let origins = CourseOrigins(student: student, career: career, programmes: programmes, otherPlans: others,
                                    overrides: EnrolmentOverrides.all(), weBeep: weBeep)
        let unplanned = courses.courses.filter {
            if case .outsidePlan = origins.origin(of: $0) { return true }
            return false
        }.compactMap(\.moodleID)
        await weBeep.loadSelfEnrolment(for: unplanned)
    }
}

import Foundation

/// What the study plan needs from the student's exam record.
///
/// ``StudyProgrammeModel`` held the whole ``CareerModel`` to read three of its
/// members. That is the coupling this redesign has been removing everywhere
/// else: a module that names a concrete stateful model cannot be built without
/// it, and ``CareerModel`` in turn wants an account, a feed and a queue — so
/// the largest module in the app had no test at all.
@MainActor
protocol StudentRecord: AnyObject, Sendable {
    /// Every teaching in the plan, passed or not. The plan matches against
    /// these to tell which of the catalogue's rows the student is actually on.
    var libretto: [LibrettoExam] { get }
    /// What the plan is *for* — the degree course, where the service says.
    var planHeader: StudyPlanHeader? { get }
    /// Ensures the record is loaded before the plan reasons about it.
    func load(force: Bool) async
}

extension CareerModel: StudentRecord {}

/// The enrolments the plan may look across.
///
/// Two members, because that is all it reads: which matricole this person has
/// (so the plan knows which it has already seen), and which enrolment is in
/// use — the plan header says "Laurea di primo livello" where the careers list
/// only says "Studente", so one fills the other's gap.
@MainActor
protocol Enrolments: AnyObject, Sendable {
    var matricole: [String] { get }
    var current: Career? { get }
}

extension CareersModel: Enrolments {
    var matricole: [String] { careers.map(\.matricola) }
}

/// The catalogue queries the study plan asks of the Manifesti site.
///
/// Seven, which is a large interface for one protocol — but it is a *query*
/// interface, and these are seven different questions rather than seven steps
/// of one. Shrinking it would mean merging questions that callers ask
/// separately, which buys nothing and costs clarity.
///
/// It exists because ``ManifestiModel`` builds its own `URLSession` against a
/// site that answers only HTML: naming what the plan asks of it is the only
/// way to stand the plan up without the network.
@MainActor
protocol ManifestoReading: AnyObject, Sendable {
    func cataloguePage(_ selection: CatalogueSelection?,
                       language: PoliMiLanguage) async -> CataloguePage?
    func locateDegree(choosing choose: ([CatalogueOption]) -> CatalogueOption?) async -> CataloguePage?
    func locateDegree(named degree: String, kind: String?) async -> CataloguePage?
    func offeringRows(teachingCode: String, yearCode: String) async -> [ManifestoTeaching]?
    func detail(for teaching: ManifestoTeaching) async -> ManifestoDetail?
    func brackets(for teaching: ManifestoTeaching) async -> [BracketChoice]
    func syllabusPick(teachingCode: String, surname: String?, degreeName: String?,
                      yearCode: String?) async -> SyllabusPicker.Pick?
}

extension ManifestiModel: ManifestoReading {}

/// The defaults the concrete type spells on its own methods.
///
/// A protocol requirement cannot carry a default argument, and making every
/// caller pass `language: .current` would be the seam charging rent. These
/// restore the call sites to what they read like before.
extension ManifestoReading {
    func cataloguePage(_ selection: CatalogueSelection?) async -> CataloguePage? {
        await cataloguePage(selection, language: .current)
    }

    func locateDegree(named degree: String) async -> CataloguePage? {
        await locateDegree(named: degree, kind: nil)
    }

    func syllabusPick(teachingCode: String, surname: String?,
                      degreeName: String?) async -> SyllabusPicker.Pick? {
        await syllabusPick(teachingCode: teachingCode, surname: surname,
                           degreeName: degreeName, yearCode: nil)
    }
}

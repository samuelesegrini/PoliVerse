import Foundation

/// The teaching codes the study plan can supply for courses that have none.
///
/// Two members, and they are the only reason ``CourseModel`` knew about the
/// 504-line ``StudyProgrammeModel`` at all. WeBeep pages titled with a name
/// only carry no code, and without one their scheda, their sittings and their
/// study-plan label do not work — so the plan is asked to fill them in.
@MainActor
protocol TeachingCodes: AnyObject, Sendable {
    /// The codes the enrolled courses already carry, by academic year, so the
    /// plan knows what it does not need to look up.
    var enrolledCodes: [String: Set<String>] { get set }
    /// A code per course id, for those the plan can place.
    func codes(for courses: [Course]) async -> [String: String]
}


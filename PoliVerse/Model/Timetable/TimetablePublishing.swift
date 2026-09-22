import Foundation

/// Where a built personal timetable goes.
///
/// One member, which is unusually thin for a protocol — but it is the whole of
/// what ``PersonalTimetableModel`` wanted from the 268-line ``AgendaModel``,
/// and a one-member seam is cheaper than a model dependency that drags the
/// agenda's account, window and offline copy along with it.
///
/// The direction is worth noting: the timetable *publishes* to the agenda
/// rather than the agenda reading from it, because the agenda merges what it
/// is given with what the Politecnico sent.
@MainActor
protocol TimetablePublishing: AnyObject, Sendable {
    var personalTimetable: PersonalTimetable? { get set }
}


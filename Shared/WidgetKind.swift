import Foundation

/// The widget kinds, named once for the extension that declares them and the app
/// that asks them to reload.
///
/// The raw value is the `kind` string each `Widget` is declared with, so
/// ``WidgetReloader`` can reload one kind rather than all of them.
nonisolated enum WidgetKind: String, Sendable, CaseIterable {
    /// The Oggi widget: the day's lectures and deadlines.
    case today = "Today"
    /// The next-lecture widget: one lecture, with its room and time.
    case nextLecture = "NextLecture"
    /// The career widget: average, credits and the next sitting.
    case career = "Career"
    /// The free-rooms widget, configured per campus.
    case freeRooms = "FreeRooms"

    /// Every kind that reads the shared agenda file, and so needs reloading when the
    /// timetable changes.
    static let agenda: Set<WidgetKind> = [.today, .nextLecture, .career]
}

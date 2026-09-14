import Foundation

/// The widget kinds, named once for both the extension that declares them and
/// the app that asks them to reload.
///
/// They used to be string literals in the extension only, which is why the
/// app could only ever say "reload everything": it had no names to be more
/// precise with.
nonisolated enum WidgetKind: String, Sendable, CaseIterable {
    case today = "Today"
    case nextLecture = "NextLecture"
    case career = "Career"
    case freeRooms = "FreeRooms"

    /// Every kind that reads the agenda file.
    static let agenda: Set<WidgetKind> = [.today, .nextLecture, .career]
}

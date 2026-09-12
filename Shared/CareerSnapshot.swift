import Foundation

/// The handful of career figures a widget can show, written by the app for
/// the extension to read.
///
/// Deliberately *not* the service's own cache. That holds the whole libretto,
/// the plan header and a pile of DTOs, none of which a widget needs and all of
/// which would have to move into the extension's compilation to be decodable.
/// A narrow, explicit snapshot means the widget's contract is visible in one
/// type, and changing how the career is cached does not break the Home Screen.
nonisolated struct CareerSnapshot: Codable, Sendable, Equatable {
    var mean: Double
    var earnedCFU: Int
    var plannedCFU: Int
    var examsGiven: Int
    var examsPlanned: Int
    /// The soonest exam sitting still ahead, if any.
    var nextExamName: String?
    var nextExamDate: Date?

    /// Where it lives in the shared store.
    static let cacheName = "career-snapshot"

    var progress: Double {
        guard plannedCFU > 0 else { return 0 }
        return min(Double(earnedCFU) / Double(plannedCFU), 1)
    }

    /// Degree mark out of 110, before any bonus for thesis or timeliness.
    var baseGraduationMark: Double { mean * 110 / 30 }

    /// Whether there is anything worth drawing.
    ///
    /// A fresh account with no results yet would otherwise render a confident
    /// "0.0 / 110", which is worse than saying nothing.
    var hasResults: Bool { earnedCFU > 0 || mean > 0 }
}

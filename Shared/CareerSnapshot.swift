import Foundation

/// The career figures a widget can show, written by the app into the shared
/// container for the extension to read.
///
/// Deliberately narrower than the career service's own cache, which holds the
/// whole libretto and its DTOs — none of which a widget needs and all of which
/// would have to compile into the extension to be decodable. The widget's
/// contract is this one type.
///
/// Stored under ``cacheName`` in ``OfflineStore``.
nonisolated struct CareerSnapshot: Codable, Sendable, Equatable {
    /// The weighted average of the marks recorded so far, out of 30.
    var mean: Double
    /// Credits already earned.
    var earnedCFU: Int
    /// Credits the study plan totals, the denominator of ``progress``.
    var plannedCFU: Int
    /// Exams with a recorded result.
    var examsGiven: Int
    /// Exams the study plan contains.
    var examsPlanned: Int
    /// The teaching of the soonest sitting still ahead, or `nil` when there is none.
    var nextExamName: String?
    /// When that sitting is, or `nil` when there is none.
    var nextExamDate: Date?

    /// The record name this snapshot is stored under in the shared store.
    static let cacheName = "career-snapshot"

    /// Credits earned as a fraction of credits planned, clamped to 1. Zero when the
    /// plan totals no credits.
    var progress: Double {
        guard plannedCFU > 0 else { return 0 }
        return min(Double(earnedCFU) / Double(plannedCFU), 1)
    }

    /// The degree mark out of 110 implied by ``mean``, before any bonus for the thesis
    /// or for finishing on time.
    var baseGraduationMark: Double { mean * 110 / 30 }

    /// Whether there is anything worth drawing.
    ///
    /// `false` for an account with no results yet, which the widget reports instead of
    /// rendering a confident zero.
    var hasResults: Bool { earnedCFU > 0 || mean > 0 }
}

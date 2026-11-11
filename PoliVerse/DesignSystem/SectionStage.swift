import Foundation

/// What a section of a screen draws, from where its part is and how long the
/// student has been looking at nothing.
///
/// The one decision every section makes the same way, kept apart from the views so
/// it can be checked without a screen: content when there is some; nothing at all
/// for the first instants, because most waits end there and a waiting line that
/// flashes is worse than a blank; then a waiting line; then, for a wait long enough
/// to wonder about, what is being waited for.
nonisolated enum SectionStage: Equatable, Sendable {
    /// The section's own rows.
    case content
    /// Nothing, at the height the section had last time.
    case quiet
    /// The waiting line, with the step in progress once the wait is long.
    case waiting(showsStep: Bool)
    /// The empty-state message: the part answered, and there is nothing in it.
    case empty
    /// The failure line with its retry.
    case failed(String)

    /// How long a section stays blank before it says it is waiting.
    static let quietTime: Duration = .milliseconds(300)
    /// How long before a waiting section also says what it is waiting for.
    static let patience: Duration = .seconds(3)

    /// The stage for a part.
    ///
    /// - Parameters:
    ///   - phase: Where the part is.
    ///   - hasRows: Whether the section has anything of its own to draw. Rows on
    ///     screen stay on screen whatever the part is doing.
    ///   - waited: How long this section has been on screen without rows, when
    ///     that is longer than the phase itself says.
    init(_ phase: LoadPhase, hasRows: Bool, waited: Duration = .zero) {
        guard !hasRows else {
            self = .content
            return
        }
        switch phase {
        case .waiting(let since):
            let total = max(since, waited)
            self = total < Self.quietTime ? .quiet : .waiting(showsStep: total >= Self.patience)
        case .failed(let message):
            self = .failed(message)
        case .empty, .held, .late, .arrived:
            // The part answered, or a stored answer is held, and none of it is
            // for this section.
            self = .empty
        }
    }

    /// How long until waiting alone changes the stage, or `nil` when it no longer will.
    ///
    /// - Parameter waited: How long the section has waited so far.
    static func nextChange(after waited: Duration) -> Duration? {
        if waited < quietTime { return quietTime - waited }
        if waited < patience { return patience - waited }
        return nil
    }
}

/// The timing of a section's reveal: who starts when, so that everything is in
/// place within ``total`` however many rows there are.
nonisolated enum RevealPlan {
    /// The whole reveal of a section, in seconds.
    static let total: TimeInterval = 0.6
    /// One row's own fade.
    static let item: TimeInterval = 0.3
    /// How much later each row starts than the one above it.
    static let stagger: TimeInterval = 0.05
    /// The whole reveal with Reduce Motion: one cross-fade.
    static let reduced: TimeInterval = 0.2
    /// How many lines of a text are revealed piece by piece; the rest fade as one.
    static let lines = 3
    /// The glyphs revealed together, about a word.
    static let glyphsPerUnit = 5
    /// The share of a text's reveal that one of its pieces takes.
    static let window = 0.45

    /// How long after the reveal starts a row begins to appear.
    ///
    /// The rows far down a long list start together with the last one that still
    /// fits, rather than after the reveal should be over.
    ///
    /// - Parameter order: The row's place in the section, from 0.
    static func delay(order: Int) -> TimeInterval {
        min(Double(max(0, order)) * stagger, total - item)
    }

    /// How far one piece of a text is into its own appearance.
    ///
    /// - Parameters:
    ///   - index: The piece's place, from 0.
    ///   - count: How many pieces there are.
    ///   - overall: How far the whole reveal is, 0 to 1.
    /// - Returns: 0 while the piece has not started, 1 once it is in place.
    static func progress(ofUnit index: Int, of count: Int, at overall: Double) -> Double {
        guard overall < 1 else { return 1 }
        guard count > 1 else { return min(1, max(0, overall)) }
        let start = Double(index) / Double(count - 1) * (1 - window)
        return min(1, max(0, (overall - start) / window))
    }
}

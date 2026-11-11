import Foundation

/// How long a part is waited for before its stored copy is said to stand in.
///
/// Values in, decision out: no clock of its own. A part that answers within the
/// deadline is simply shown. One that does not, and has a stored copy, is shown
/// from that copy with its age, and the request goes on: a late answer is still
/// the freshest data, and asking again would only add load to a host that is
/// already slow.
nonisolated struct DeadlinePolicy: Equatable, Sendable {
    /// What to do about a part that has not answered yet.
    enum Decision: Equatable, Sendable {
        /// Keep waiting: it is early, or there is nothing else to show.
        case wait
        /// Show the stored copy, with its age, and keep the request running.
        case showStored
    }

    /// How long a part may take before its stored copy stands in.
    var deadline: Duration = .seconds(4)

    /// The decision for one part.
    ///
    /// - Parameters:
    ///   - waited: How long ago the part was asked for.
    ///   - hasStoredCopy: Whether a copy of it is held, restored or fetched earlier.
    func decision(waited: Duration, hasStoredCopy: Bool) -> Decision {
        hasStoredCopy && waited >= deadline ? .showStored : .wait
    }
}

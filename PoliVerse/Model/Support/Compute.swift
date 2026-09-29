import Foundation

/// The compute lane: work proportional to a payload, run off the main actor.
///
/// With Approachable Concurrency a `nonisolated` function runs on its caller: a
/// synchronous parser called from a `@MainActor` model parses on the main thread,
/// and a `nonisolated async` one does too until its first suspension. `@concurrent`
/// is the attribute that leaves, so the parsers, indexes and planners the models
/// call directly go through here.
///
/// For what scales with the size of a page, a response or a timetable. A constant
/// amount of work is cheaper where it is than the hop to another thread.
nonisolated enum Compute {
    /// Runs synchronous work on the global pool and returns its result.
    ///
    /// - Parameter work: The work. Captures only `Sendable` values.
    /// - Returns: What the work returned.
    @concurrent
    static func run<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T {
        try work()
    }
}

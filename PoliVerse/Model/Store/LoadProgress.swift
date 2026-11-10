import Foundation

/// Where a fetch hands over what it has so far, part by part.
///
/// A resource that takes several requests reports a value built from the parts that have answered, and says which parts
/// those are. Whoever waits on the fetch reads ``snapshots``.
///
/// Only the newest snapshot not yet read is kept. A campus of rooms answers in
/// bursts, and a screen that redrew for every answer would spend the load
/// redrawing; with one slot, however many reports land between two reads cost one
/// assignment.
///
/// Named `LoadProgress` rather than `Progress`, which Foundation already has.
nonisolated struct LoadProgress<R: Resource>: Sendable {
    /// What a fetch has at one moment.
    struct Snapshot: Sendable {
        /// The value, built from the parts that arrived over whatever was held.
        var value: R.Value
        /// The parts in ``value`` that have answered in this fetch.
        var arrived: Set<R.Part>
        /// The parts whose request failed in this fetch.
        var failed: Set<R.Part>
    }

    /// The snapshots, newest only. Ends when the fetch calls ``finish()``.
    let snapshots: AsyncStream<Snapshot>
    private let continuation: AsyncStream<Snapshot>.Continuation

    /// Creates a handle nobody has read from yet.
    init() {
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Hands over what the fetch has so far.
    ///
    /// - Parameters:
    ///   - value: The value built from the parts that have arrived.
    ///   - arrived: Those parts.
    ///   - failed: The parts whose request failed.
    func report(_ value: R.Value, arrived: Set<R.Part>, failed: Set<R.Part> = []) {
        continuation.yield(Snapshot(value: value, arrived: arrived, failed: failed))
    }

    /// Says nothing more is coming.
    func finish() {
        continuation.finish()
    }
}

/// The state of one section of a screen: the one thing its view switches on.
///
/// Replaces reading `isLoading`, `isEmpty` and `errorMessage` together, which is
/// how a screen ends up saying "no exams" while the exams are still on their way.
nonisolated enum LoadPhase: Equatable, Sendable {
    /// A stored copy is shown, fetched this long ago.
    case held(age: TimeInterval)
    /// Nothing to show yet; the request left this long ago.
    case waiting(since: Duration)
    /// The part answered with content.
    case arrived
    /// The part answered, and there is nothing in it.
    case empty
    /// The part failed and there is no stored copy.
    case failed(String)

    /// Whether the section has real data on screen.
    var showsContent: Bool {
        switch self {
        case .held, .arrived: true
        case .waiting, .empty, .failed: false
        }
    }

    /// Whether an empty-state message may be shown: only once the part has answered.
    var mayShowEmptyState: Bool { self == .empty }
}

import Foundation

/// The one place every request to the Politecnico passes through.
///
/// It times each request and notes it in the ``LoadingLedger`` with what
/// ``LoadContext`` says it was for, and it keeps the ``HostBreaker``: a host that
/// timed out twice in a row is not asked for half a minute, and requests to it
/// throw ``HostPaused`` at once, so a screen shows its stored copy without
/// waiting. It is an actor because it is also where the lanes for on-screen and
/// speculative requests will keep their state.
actor RequestGate {
    /// The app's gate, noting into the app's ledger.
    nonisolated static let shared = RequestGate(ledger: .shared)

    private let ledger: LoadingLedger
    private var breaker: HostBreaker
    private let now: @Sendable () -> ContinuousClock.Instant
    private let pauseChanged: @Sendable (String, Duration?) -> Void

    /// Creates a gate.
    ///
    /// - Parameters:
    ///   - ledger: Where requests are noted.
    ///   - breaker: Decides when a host is paused.
    ///   - now: The clock the pauses run on.
    ///   - pauseChanged: Told the host and for how long it is paused, or `nil`
    ///     when it answers again. The app's gate writes to ``HostPauses/shared``.
    init(ledger: LoadingLedger, breaker: HostBreaker = HostBreaker(),
         now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
         pauseChanged: @escaping @Sendable (String, Duration?) -> Void = { host, pause in
             Task { @MainActor in HostPauses.shared.set(host, pausedFor: pause) }
         }) {
        self.ledger = ledger
        self.breaker = breaker
        self.now = now
        self.pauseChanged = pauseChanged
    }

    /// Whether requests to a host are being answered without being sent.
    ///
    /// - Parameter host: The service, by name.
    func isPaused(_ host: String) -> Bool {
        breaker.isPaused(host, at: now())
    }

    /// Tells the breaker how a request ended.
    private func record(_ outcome: LedgerRequest.Outcome, host: String) {
        switch breaker.note(outcome, host: host, at: now()) {
        case .paused(let pause): pauseChanged(host, pause)
        case .resumed: pauseChanged(host, nil)
        case nil: break
        }
    }

    /// Runs a request and notes how long it took and how it ended.
    ///
    /// - Parameters:
    ///   - host: The service asked, by name. Never a URL.
    ///   - pausable: Whether the request may be answered with ``HostPaused``
    ///     while its host is paused. `false` for what the student did, such as
    ///     enrolling in an exam: that is always sent.
    ///   - request: The request itself.
    /// - Returns: What the request returned.
    /// - Throws: What the request threw, unchanged, or ``HostPaused`` without
    ///   sending it.
    nonisolated func run<T: Sendable>(
        host: String, pausable: Bool = true, _ request: @Sendable () async throws -> T
    ) async throws -> T {
        if pausable, await isPaused(host) { throw HostPaused(host: host) }
        let context = LoadContext.current
        let start = Date.now
        let clock = ContinuousClock()
        let began = clock.now
        func note(_ outcome: LedgerRequest.Outcome) {
            let elapsed = clock.now - began
            let milliseconds = Int(elapsed.components.seconds) * 1000
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            ledger.note(LedgerRequest(
                part: context?.part ?? LoadContext.unattributed, host: host, start: start,
                milliseconds: milliseconds, outcome: outcome,
                speculative: context?.speculative ?? false))
        }
        do {
            let value = try await request()
            note(.ok)
            await record(.ok, host: host)
            return value
        } catch {
            let outcome = Self.outcome(of: error)
            note(outcome)
            await record(outcome, host: host)
            throw error
        }
    }

    /// How a request that threw `error` ended.
    ///
    /// - Parameter error: What the request threw.
    /// - Returns: ``LedgerRequest/Outcome/cancelled`` for a caller that went away,
    ///   ``LedgerRequest/Outcome/timedOut`` for a timeout, otherwise
    ///   ``LedgerRequest/Outcome/failed``.
    nonisolated static func outcome(of error: any Error) -> LedgerRequest.Outcome {
        var underlying = error
        if let api = error as? APIError {
            switch api {
            case .cancelled: return .cancelled
            case .transport(let inner): underlying = inner
            default: break
            }
        }
        if PoliMiAPI.isCancellation(underlying) { return .cancelled }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut { return .timedOut }
        return .failed
    }
}

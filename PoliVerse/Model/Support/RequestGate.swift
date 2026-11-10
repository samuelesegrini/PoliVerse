import Foundation

/// The one place every request to the Politecnico passes through.
///
/// Today it only watches: it times each request and notes it in the
/// ``LoadingLedger`` with what ``LoadContext`` says it was for. It is an actor
/// because it is where the lanes for on-screen and speculative requests, and the
/// per-host pause after repeated timeouts, will keep their state.
actor RequestGate {
    /// The app's gate, noting into the app's ledger.
    nonisolated static let shared = RequestGate(ledger: .shared)

    private let ledger: LoadingLedger

    /// Creates a gate.
    ///
    /// - Parameter ledger: Where requests are noted.
    init(ledger: LoadingLedger) {
        self.ledger = ledger
    }

    /// Runs a request and notes how long it took and how it ended.
    ///
    /// - Parameters:
    ///   - host: The service asked, by name. Never a URL.
    ///   - request: The request itself.
    /// - Returns: What the request returned.
    /// - Throws: What the request threw, unchanged.
    nonisolated func run<T: Sendable>(
        host: String, _ request: @Sendable () async throws -> T
    ) async throws -> T {
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
            return value
        } catch {
            note(Self.outcome(of: error))
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

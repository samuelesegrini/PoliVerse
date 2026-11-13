import Foundation

/// A load state forced from the launch arguments, to see and photograph the screens in it:
/// `-ForceLoading`, `-ForceError` or `-ForceOffline`. Debug builds only; a release build has
/// none, whatever it is launched with.
///
/// The ``Loader`` applies it to every fetch, the sample data's included, and ``DataStatus``
/// says it in the status line, so each screen shows its own loading, error or offline state
/// rather than a stand-in.
nonisolated enum DebugLoadState: String, Sendable, CaseIterable {
    /// Every fetch waits and never answers.
    case loading
    /// Every fetch fails as a server error would.
    case error
    /// The network is gone: what is held is shown as the offline copy.
    case offline

    /// The launch argument for each state.
    var argument: String {
        switch self {
        case .loading: "-ForceLoading"
        case .error: "-ForceError"
        case .offline: "-ForceOffline"
        }
    }

    /// The state the arguments ask for, the first named; `nil` with none.
    ///
    /// - Parameter arguments: The process's arguments.
    static func parse(_ arguments: [String]) -> DebugLoadState? {
        allCases.first { arguments.contains($0.argument) }
    }

    /// The state this run was launched with; always `nil` outside debug builds.
    static let current: DebugLoadState? = {
        #if DEBUG
        parse(CommandLine.arguments)
        #else
        nil
        #endif
    }()

    /// The error a forced failure throws.
    var failure: (any Error)? {
        switch self {
        case .loading: nil
        case .error: APIError.badStatus(503, body: "ForceError")
        case .offline: APIError.transport(URLError(.notConnectedToInternet))
        }
    }
}

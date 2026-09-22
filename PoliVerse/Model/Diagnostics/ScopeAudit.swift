import Foundation

/// The OAuth scopes the Politecnico asks for today, against the ones the stored token
/// was minted with.
///
/// A token carries only what was requested when it was created, and refreshing never
/// widens it, so a changed scope list makes an old token fail on the new service with a
/// 401 that looks exactly like a broken sign-in. ``LoginFlow/restore()``
/// re-authenticates on any difference; this names the difference, so the diagnostics
/// page can say which scope is missing.
nonisolated struct ScopeAudit: Equatable, Sendable {
    /// Requested today but absent from the token, in the order requested.
    let missing: [String]
    /// On the token but no longer requested, in the order recorded.
    let retired: [String]
    /// How many distinct scopes are requested today.
    let requestedCount: Int
    /// How many of today's scopes the token carries. Zero when the token's scope is
    /// unknown.
    var grantedCount: Int { isUnknown ? 0 : requestedCount - missing.count }
    /// Whether the token predates the app recording its scope.
    ///
    /// Never treated as fine: those are precisely the tokens minted before a scope change.
    let isUnknown: Bool

    /// Whether the token was minted for exactly today's list — the same test
    /// ``LoginFlow/restore()`` applies before restoring a session.
    var isCurrent: Bool { !isUnknown && missing.isEmpty && retired.isEmpty }

    /// Compares the two lists.
    ///
    /// - Parameters:
    ///   - current: Today's space-separated scope list.
    ///   - recorded: The list stored with the token, or `nil` when none was.
    init(current: String, recorded: String?) {
        let requested = Self.scopes(in: current)
        requestedCount = requested.count
        guard let recorded else {
            missing = []
            retired = []
            isUnknown = true
            return
        }
        let granted = Self.scopes(in: recorded)
        missing = requested.filter { !granted.contains($0) }
        retired = granted.filter { !requested.contains($0) }
        isUnknown = false
    }

    /// The distinct scopes in a list, in first-seen order.
    ///
    /// Split on any whitespace, since the fallback list is written with doubled spaces and
    /// newlines, and compared as a set, since order means nothing to the identity provider.
    ///
    /// - Parameter list: The space-separated scope list.
    /// - Returns: The scopes.
    private static func scopes(in list: String) -> [String] {
        var seen = Set<String>()
        return list.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }
}

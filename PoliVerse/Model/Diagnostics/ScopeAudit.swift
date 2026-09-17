import Foundation

/// The scopes the Politecnico asks for today, against the ones the stored
/// token was minted with.
///
/// A token only carries what was requested when it was created, and
/// refreshing never widens it. When the list changes — it did in 2026, adding
/// `agenda` and dropping `esami` — the old token fails on the new service with
/// a 401 that looks exactly like a broken login. ``Session`` re-authenticates
/// on any difference; this names the difference, so the diagnostics page can
/// say *which* scope is missing instead of "non autorizzati".
nonisolated struct ScopeAudit: Equatable, Sendable {
    /// Requested today but absent from the token, in the order requested.
    let missing: [String]
    /// On the token but no longer requested, in the order recorded.
    let retired: [String]
    /// How many distinct scopes are requested today.
    let requestedCount: Int
    /// How many of today's scopes the token carries.
    var grantedCount: Int { isUnknown ? 0 : requestedCount - missing.count }
    /// The token predates the app recording its scope. Never "fine": those are
    /// precisely the tokens minted before a scope change.
    let isUnknown: Bool

    /// Whether the token was minted for exactly today's list — the same test
    /// ``Session`` applies before restoring a session.
    var isCurrent: Bool { !isUnknown && missing.isEmpty && retired.isEmpty }

    /// - Parameters:
    ///   - current: today's space-separated scope list.
    ///   - recorded: the list stored with the token, nil if none was stored.
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

    /// Distinct scopes in first-seen order. Compared as a set: the fallback
    /// list is built with doubled spaces and newlines, and order carries no
    /// meaning to the identity provider.
    private static func scopes(in list: String) -> [String] {
        var seen = Set<String>()
        return list.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }
}

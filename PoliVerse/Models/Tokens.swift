import Foundation

/// OAuth token pair issued by the Politecnico IdP (`oauthidp.polimi.it`).
///
/// The `polimiapp` REST layer returns camelCase keys, unlike the Microsoft leg
/// used by PoliFemo, so no custom `CodingKeys` are needed here.
nonisolated struct PoliMiToken: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int

    /// Absolute expiry, computed when the token is minted rather than stored by
    /// the server. PoliFemo never persisted this and so could not refresh
    /// proactively — it only reacted to a 401.
    var issuedAt: Date = .now

    /// The scope string this token was minted with.
    ///
    /// A token carries the scopes it was granted at creation and refreshing
    /// does not widen them. So when the Politecnico adds a scope — `agenda`
    /// appeared after 2023 — an existing token keeps working for everything it
    /// already covered and returns 401 for the new service, forever. Recording
    /// the scope lets the app notice and re-authenticate instead of leaving the
    /// user stuck on a quietly half-broken session.
    var grantedScope: String?

    var expiresAt: Date { issuedAt.addingTimeInterval(TimeInterval(expiresIn)) }

    /// Treat a token as stale slightly early so an in-flight request does not
    /// expire between the check and the server receiving it.
    func isExpired(leeway: TimeInterval = 60) -> Bool {
        Date.now.addingTimeInterval(leeway) >= expiresAt
    }

    /// `issuedAt` and `grantedScope` are ours, not the server's, so they are
    /// excluded from decoding but kept when the token is persisted.
    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresIn
    }

    /// Persisted form, including the fields the server does not send.
    struct Stored: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresIn: Int
        var issuedAt: Date
        var grantedScope: String?

        init(_ token: PoliMiToken) {
            accessToken = token.accessToken
            refreshToken = token.refreshToken
            expiresIn = token.expiresIn
            issuedAt = token.issuedAt
            grantedScope = token.grantedScope
        }

        var token: PoliMiToken {
            PoliMiToken(
                accessToken: accessToken, refreshToken: refreshToken,
                expiresIn: expiresIn, issuedAt: issuedAt, grantedScope: grantedScope
            )
        }
    }
}

import Foundation

/// An OAuth token pair issued by the Politecnico identity provider at
/// `oauthidp.polimi.it`.
///
/// Decoded straight from the `polimiapp` REST layer, which sends camelCase keys.
/// ``issuedAt`` and ``grantedScope`` are computed by the app rather than sent by
/// the server, so they are excluded from decoding and carried in ``Stored`` when
/// the token is persisted.
nonisolated struct PoliMiToken: Codable, Sendable, Equatable {
    /// The bearer token sent with each request.
    var accessToken: String
    /// The token exchanged for a new pair when the access token expires.
    var refreshToken: String
    /// Lifetime of the access token in seconds, as issued.
    var expiresIn: Int

    /// When the pair was minted, recorded by the app so that ``expiresAt`` is known and
    /// a refresh can happen before a request fails.
    var issuedAt: Date = .now

    /// The scope string this pair was minted with.
    ///
    /// A token carries the scopes granted at creation, and refreshing does not widen
    /// them, so a pair minted before a scope existed keeps working for everything it
    /// already covered and returns 401 for the new service indefinitely. Recording the
    /// scope lets ``TokenStore`` notice and re-authenticate.
    var grantedScope: String?

    /// When the access token stops being valid.
    var expiresAt: Date { issuedAt.addingTimeInterval(TimeInterval(expiresIn)) }

    /// Whether the access token should be treated as expired.
    ///
    /// - Parameter leeway: How far ahead of ``expiresAt`` to call it expired, so an
    ///   in-flight request does not expire between the check and the server receiving
    ///   it.
    /// - Returns: `true` when the token is expired or about to be.
    func isExpired(leeway: TimeInterval = 60) -> Bool {
        Date.now.addingTimeInterval(leeway) >= expiresAt
    }

    /// Only the three fields the server sends. ``issuedAt`` and ``grantedScope`` are
    /// the app's own.
    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresIn
    }

    /// The persisted form of a token pair, including the fields the server does not
    /// send.
    struct Stored: Codable, Sendable {
        /// The bearer token.
        var accessToken: String
        /// The refresh token.
        var refreshToken: String
        /// Lifetime of the access token in seconds.
        var expiresIn: Int
        /// When the pair was minted.
        var issuedAt: Date
        /// The scope the pair was minted with.
        var grantedScope: String?

        /// Captures a token for persistence.
        ///
        /// - Parameter token: The pair to store.
        init(_ token: PoliMiToken) {
            accessToken = token.accessToken
            refreshToken = token.refreshToken
            expiresIn = token.expiresIn
            issuedAt = token.issuedAt
            grantedScope = token.grantedScope
        }

        /// The stored pair, back as a ``PoliMiToken``.
        var token: PoliMiToken {
            PoliMiToken(
                accessToken: accessToken, refreshToken: refreshToken,
                expiresIn: expiresIn, issuedAt: issuedAt, grantedScope: grantedScope
            )
        }
    }
}

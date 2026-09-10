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

    var expiresAt: Date { issuedAt.addingTimeInterval(TimeInterval(expiresIn)) }

    /// Treat a token as stale slightly early so an in-flight request does not
    /// expire between the check and the server receiving it.
    func isExpired(leeway: TimeInterval = 60) -> Bool {
        Date.now.addingTimeInterval(leeway) >= expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresIn
    }
}

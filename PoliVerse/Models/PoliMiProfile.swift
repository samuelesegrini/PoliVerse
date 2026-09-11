import Foundation

/// The signed-in user's profile type, sent as `poliAuthProfile`.
///
/// Values taken from the official web app's own guards:
///
/// ```js
/// L_e = n => n === 1    // student
/// VBe = n => n === 2
/// T_e = n => n === 4    // alumni
/// ```
///
/// Distinct from the `iae.profile` / `libretto.profile` values in
/// `/jaf/public/props`, which are `0` and control whether a call appends a
/// `matricola` query parameter. Conflating the two sends `poliAuthProfile: 0`,
/// which matches no profile.
nonisolated enum PoliMiProfile {
    static let student = 1
    static let alumni = 4

    /// Fallback when the profile list cannot be read.
    static let `default` = student
}

/// Wire shape of `/jaf/internal/profiles`.
///
/// - Note: the exact field names are **unverified** — the endpoint needs a
///   token, so it could not be inspected from outside. Every field is optional
///   and several plausible spellings are accepted; `Session` logs the raw body
///   on the first fetch so the real shape can be pinned down and this trimmed.
nonisolated struct PoliMiProfileDTO: Decodable, Sendable {
    let profile: Int?
    let idProfilo: Int?
    let codiceProfilo: Int?
    let tipoProfilo: Int?

    /// First non-nil candidate.
    var identifier: Int? { profile ?? idProfilo ?? codiceProfilo ?? tipoProfilo }
}

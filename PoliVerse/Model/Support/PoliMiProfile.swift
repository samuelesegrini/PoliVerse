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

    /// What `poliAuthD_profile` carries when the account has no secondary
    /// profile. A literal sentinel, not an empty string — `u_.D_PROFILE_VUOTO`
    /// in the official bundle.
    static let emptyDProfile = "JAF_D_PROFILE_VUOTO"
}

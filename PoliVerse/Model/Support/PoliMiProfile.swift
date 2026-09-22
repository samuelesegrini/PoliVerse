import Foundation

/// The profile values the identity service sends as `poliAuthProfile`.
///
/// Distinct from the `iae.profile` and `libretto.profile` values in
/// `/jaf/public/props`, which are `0` and control whether a call appends a
/// `matricola` query parameter. Sending `poliAuthProfile: 0` matches no profile.
nonisolated enum PoliMiProfile {
    /// An enrolled student.
    static let student = 1
    /// A graduate.
    static let alumni = 4

    /// Used when the profile list cannot be read.
    static let `default` = student

    /// What `poliAuthD_profile` carries when the account has no secondary profile.
    ///
    /// A literal sentinel rather than an empty string.
    static let emptyDProfile = "JAF_D_PROFILE_VUOTO"
}

import Foundation

/// One entry of `/jaf/internal/profiles`, which supplies the profile values the
/// transport puts in its headers.
///
/// ```json
/// [{"profile":1,"description":"Student","dprofile":null,
///   "profileDescription":"Student","dprofileDescription":null,
///   "dprofileValue":null}]
/// ```
nonisolated struct PoliMiProfileDTO: Decodable, Sendable {
    /// The profile value sent as `poliAuthProfile`. See ``PoliMiProfile``.
    let profile: Int?
    /// The profile's name, for diagnostics.
    let description: String?
    /// Secondary profile, sent as `poliAuthD_profile`. Null for a plain student
    /// account, in which case ``PoliMiProfile/emptyDProfile`` is sent.
    let dprofile: String?

    /// ``profile``, under the name the transport reads.
    var identifier: Int? { profile }
}

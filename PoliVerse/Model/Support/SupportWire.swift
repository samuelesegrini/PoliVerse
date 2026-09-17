import Foundation

/// The shape `/jaf/public/props` sends for the profile values the transport
/// puts in its headers.

/// Wire shape of `/jaf/internal/profiles`.
///
/// Shape confirmed against a real account:
///
/// ```json
/// [{"profile":1,"description":"Student","dprofile":null,
///   "profileDescription":"Student","dprofileDescription":null,
///   "dprofileValue":null}]
/// ```
nonisolated struct PoliMiProfileDTO: Decodable, Sendable {
    let profile: Int?
    let description: String?
    /// Secondary profile, sent as `poliAuthD_profile`. Null for a plain
    /// student account.
    let dprofile: String?

    var identifier: Int? { profile }
}

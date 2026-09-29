// ActivityKit is iOS-only, and `Shared` compiles into the Watch app as well.
#if os(iOS)
import ActivityKit
import Foundation

/// The attributes of the Live Activity that follows a recording's download.
///
/// Shared between targets because both processes need it: the app starts, updates
/// and ends the activity through ``DownloadActivities``, and the widget extension
/// draws it in `RecordingDownloadLiveActivity`. `ActivityAttributes` are matched by
/// type identity across processes, so a copy per target would not be the same
/// activity.
nonisolated struct RecordingDownloadAttributes: ActivityAttributes {
    /// The recording's `transfer_id`, which the app finds the activity by after a
    /// relaunch.
    var transferID: Int
    /// The teaching's title.
    var course: String
    /// The kind of session and the day it was recorded, `"Lezione · 21 set"`.
    var detail: String
    /// The file's size as the archive rounds it, when known.
    var megabytes: Int?

    /// The part of the activity that changes while it is live.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Where the download stands.
        var phase: Phase
        /// The fraction done, from 0 to 1, when the size is known.
        var fraction: Double?

        /// Where a download stands, as the activity says it.
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            /// Bytes are arriving.
            case downloading
            /// Held back for Wi-Fi: the only connection is cellular, and the student
            /// chose not to use it for recordings.
            case waiting
            /// On the device.
            case finished
            /// Stopped when the app was closed; carried on at the next launch.
            case interrupted
            /// Did not complete.
            case failed
        }
    }
}
#endif

import Foundation

/// What Webex says about a recording: where it streams, how long it is, and what
/// the lecturer allows.
///
/// Read from `GET /webappng/api/v1/recordings/<id>/stream`, the call the Webex web
/// player makes for itself; only the fields the app uses are decoded. The addresses
/// carry a ticket that expires after ninety minutes, so a stream is never kept on
/// disk. See `docs/recordings.md`, "Webex /stream".
nonisolated struct WebexStream: Decodable, Sendable, Equatable {
    /// The HLS playlist, which `AVPlayer` plays directly.
    let hlsURL: URL?
    /// The whole recording as one MP4, for a download the lecturer allows.
    let mp4URL: URL?
    /// The length.
    let duration: Duration?
    /// The size of the MP4, in bytes.
    let fileSize: Int?
    /// Whether the lecturer, or the site, forbids downloading.
    let preventsDownload: Bool
    /// Whether Webex shows a notice before playing.
    let needsDisclaimer: Bool
    /// The recording's name on Webex.
    let name: String?

    /// Whether the recording may be saved on the device.
    var allowsDownload: Bool { !preventsDownload && mp4URL != nil }

    private enum CodingKeys: String, CodingKey {
        case downloadRecordingInfo, duration, fileSize, preventDownload, enforcePreventDownload,
             needShowDisclaimer, recordName
    }

    private enum InfoKeys: String, CodingKey { case downloadInfo }
    private enum DownloadKeys: String, CodingKey { case hlsURL, mp4URL }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let info = try? container.nestedContainer(keyedBy: InfoKeys.self, forKey: .downloadRecordingInfo)
        let download = try? info?.nestedContainer(keyedBy: DownloadKeys.self, forKey: .downloadInfo)
        hlsURL = (try? download?.decodeIfPresent(String.self, forKey: .hlsURL)).flatMap { $0 }.flatMap(URL.init(string:))
        mp4URL = (try? download?.decodeIfPresent(String.self, forKey: .mp4URL)).flatMap { $0 }.flatMap(URL.init(string:))
        duration = (try? container.decodeIfPresent(Int.self, forKey: .duration)).flatMap { $0 }.map { .milliseconds($0) }
        fileSize = (try? container.decodeIfPresent(Int.self, forKey: .fileSize)).flatMap { $0 }
        let prevent = (try? container.decodeIfPresent(Bool.self, forKey: .preventDownload)).flatMap { $0 } ?? false
        let enforce = (try? container.decodeIfPresent(Bool.self, forKey: .enforcePreventDownload)).flatMap { $0 } ?? false
        preventsDownload = prevent || enforce
        needsDisclaimer = (try? container.decodeIfPresent(Bool.self, forKey: .needShowDisclaimer)).flatMap { $0 } ?? false
        name = (try? container.decodeIfPresent(String.self, forKey: .recordName)).flatMap { $0 }
    }
}

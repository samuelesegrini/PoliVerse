#if os(macOS)
import AVFoundation
import Foundation
import Testing
@testable import PoliVerse

private final class SubtitleFixtureBundle: NSObject {}

@MainActor
@Suite("Native recording subtitle check")
struct RecordingSubtitlePlaybackTests {
    /// Opt-in window for inspecting AVKit's Language and Style menus on supported hardware.
    /// The assertion covers playback; generated captions require the separate visual check.
    @Test("Play an offline English sample in the production reader",
          .enabled(if: ProcessInfo.processInfo.environment["RUN_RECORDING_SUBTITLE_CHECK"] == "1"),
          .timeLimit(.minutes(2)))
    func offlineEnglish() async throws {
        let bundle = Bundle(for: SubtitleFixtureBundle.self)
        let url = try #require(bundle.url(forResource: "subtitles-en", withExtension: "mov")
            ?? bundle.url(forResource: "subtitles-en", withExtension: "mov", subdirectory: "Fixtures"))
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let language = try await track.load(.extendedLanguageTag)
        #expect(language?.split(separator: "-").first == "en")
        #expect(try await asset.load(.duration).seconds >= 30)
        let recording = Recording(transferID: -1, academicYear: "2026/27", recordedAt: .now,
                                  teachingCode: "TEST", courseTitle: "Synthetic English lecture",
                                  lecturer: nil, form: .lecture, topic: "Subtitle verification", minutes: 1, megabytes: 2)
        var advanced = false
        RecordingPlayer.shared.play(url, recording: recording) { position, _, _ in
            if position > 0 { advanced = true }
        }
        defer { RecordingPlayer.shared.stop() }
        try await Task.sleep(for: .seconds(60))
        #expect(advanced, "The local sample should advance through the real recording player")
    }
}
#endif

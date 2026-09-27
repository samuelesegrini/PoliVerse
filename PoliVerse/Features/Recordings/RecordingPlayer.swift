import AVKit
import OSLog
#if os(iOS)
import UIKit

/// Plays a lecture recording in the system player.
///
/// `AVPlayerViewController`, presented by UIKit rather than by a SwiftUI sheet: that
/// way AVKit can dismiss it when Picture in Picture starts and this type presents it
/// again when the student returns from Picture in Picture, which a SwiftUI
/// presentation would tear down with the player. Speed, AirPlay, the lock screen and
/// Now Playing come with the controller; the recording plays on with the screen off
/// because the app declares the `audio` background mode.
@MainActor
final class RecordingPlayer: NSObject, AVPlayerViewControllerDelegate {
    /// The one player: a second recording replaces the first.
    static let shared = RecordingPlayer()

    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// The controller on screen or in Picture in Picture, held so the second
    /// survives the first being dismissed.
    private var controller: AVPlayerViewController?
    /// Whether the recording is in Picture in Picture.
    private var inPictureInPicture = false
    /// Hears where the player is, every few seconds and once more on closing.
    private var onProgress: ((_ position: Double, _ duration: Double, _ final: Bool) -> Void)?
    /// The periodic time observer on the player.
    private var timeObserver: Any?
    /// Waits for the item to be ready before seeking to the resume point.
    private var readiness: NSKeyValueObservation?

    /// Plays a recording from its Webex stream.
    ///
    /// - Parameters:
    ///   - stream: What Webex answered, with the HLS address.
    ///   - recording: The recording, for the title on the lock screen.
    ///   - cookies: Webex's cookies from the recordings' session, sent with the media
    ///     requests in case the media host wants them as well as the ticket.
    ///   - startAt: Where to start, in seconds, or `nil` for the beginning.
    ///   - onProgress: Hears the position and length every five seconds, and once
    ///     more, marked final, when the player closes.
    func play(
        _ stream: WebexStream, recording: Recording, cookies: [HTTPCookie], startAt: Double? = nil,
        onProgress: @escaping (_ position: Double, _ duration: Double, _ final: Bool) -> Void = { _, _, _ in }
    ) {
        guard let address = stream.hlsURL else { return }
        play(address, recording: recording, cookies: cookies,
             duration: stream.duration.map { Double($0.components.seconds) } ?? 0,
             startAt: startAt, onProgress: onProgress)
    }

    /// Plays a recording from an address: Webex's HLS, or a file saved on the device.
    ///
    /// - Parameters:
    ///   - address: What to play.
    ///   - recording: The recording, for the title on the lock screen.
    ///   - cookies: Cookies for the media requests; none for a file.
    ///   - duration: The length in seconds when known, until the player measures it.
    ///   - startAt: Where to start, in seconds, or `nil` for the beginning.
    ///   - onProgress: Hears the position and length every five seconds, and once
    ///     more, marked final, when the player closes.
    func play(
        _ address: URL, recording: Recording, cookies: [HTTPCookie] = [], duration: Double = 0,
        startAt: Double? = nil,
        onProgress: @escaping (_ position: Double, _ duration: Double, _ final: Bool) -> Void = { _, _, _ in }
    ) {
        stop()

        // The category once, and the activation off the main thread: both block,
        // and changing the category of an active session is what the system warns
        // about on the second recording.
        let audio = AVAudioSession.sharedInstance()
        if audio.category != .playback || audio.mode != .moviePlayback {
            do {
                try audio.setCategory(.playback, mode: .moviePlayback)
            } catch {
                log.error("Audio session: \(error.localizedDescription, privacy: .public)")
            }
        }
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        let asset = address.isFileURL
            ? AVURLAsset(url: address)
            : AVURLAsset(url: address, options: [AVURLAssetHTTPCookiesKey: cookies])
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = Self.metadata(for: recording)
        let player = AVPlayer(playerItem: item)
        let fallbackDuration = duration
        self.onProgress = onProgress
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
        ) { [weak self, weak item] time in
            MainActor.assumeIsolated {
                let duration = item?.duration.seconds ?? .nan
                self?.onProgress?(time.seconds, duration.isFinite ? duration : fallbackDuration, false)
            }
        }

        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        // Over, not in place of, the app: a `.fullScreen` presentation takes the
        // SwiftUI root out of the window, and on its return the root's launch
        // task — the session restore — runs a second time.
        controller.modalPresentationStyle = .overFullScreen
        self.controller = controller

        guard let presenter = Self.topViewController() else { return }
        presenter.present(controller, animated: true) { [weak self] in
            guard let startAt, startAt > 0 else {
                player.play()
                return
            }
            // A seek before the item is ready is dropped, so wait for it.
            self?.readiness = item.observe(\.status, options: [.initial, .new]) { item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.readiness = nil
                    await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
                    player.play()
                }
            }
        }
        log.info("Playing transfer \(recording.transferID, privacy: .public)\(startAt.map { " from \(Int($0)) s" } ?? "", privacy: .public)")
    }

    /// Stops whatever is playing, reports where it stopped, and lets the controller go.
    func stop() {
        if let player = controller?.player {
            player.pause()
            let duration = player.currentItem?.duration.seconds ?? .nan
            onProgress?(player.currentTime().seconds, duration.isFinite ? duration : 0, true)
            if let timeObserver { player.removeTimeObserver(timeObserver) }
        }
        timeObserver = nil
        readiness = nil
        onProgress = nil
        controller = nil
        inPictureInPicture = false
    }

    // MARK: - AVPlayerViewControllerDelegate

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        inPictureInPicture = true
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        inPictureInPicture = false
    }

    /// Puts the full-screen player back when the student taps "back" on the Picture in
    /// Picture window.
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard playerViewController.presentingViewController == nil, let presenter = Self.topViewController() else {
            completionHandler(true)
            return
        }
        presenter.present(playerViewController, animated: true) { completionHandler(true) }
    }

    /// Closing the full-screen player stops the recording, unless it went on in
    /// Picture in Picture.
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled, !self.inPictureInPicture else { return }
            self.stop()
        }
    }

    // MARK: - Helpers

    /// The title and course for the lock screen and Now Playing.
    private static func metadata(for recording: Recording) -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item.copy() as! AVMetadataItem
        }
        let title = recording.topic ?? recording.form.title
        let subtitle = "\(recording.courseTitle.capitalized) · "
            + recording.recordedAt.formatted(.dateTime.day().month(.abbreviated))
        return [item(.commonIdentifierTitle, title), item(.iTunesMetadataTrackSubTitle, subtitle)]
    }

    /// The view controller on top of the key window, to present from.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#else
import AppKit

/// Plays a lecture recording in a window of its own.
///
/// The Mac's version: `AVPlayerView` in a regular window, so the recording can sit
/// beside the course's materials. Picture in Picture comes from the player's own
/// controls. Closing the window stops the recording and reports where it stopped.
@MainActor
final class RecordingPlayer: NSObject, NSWindowDelegate {
    /// The one player: a second recording replaces the first.
    static let shared = RecordingPlayer()

    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// The window showing the player.
    private var window: NSWindow?
    /// The player in the window.
    private var player: AVPlayer?
    /// Hears where the player is, every few seconds and once more on closing.
    private var onProgress: ((_ position: Double, _ duration: Double, _ final: Bool) -> Void)?
    /// The periodic time observer on the player.
    private var timeObserver: Any?
    /// Waits for the item to be ready before seeking to the resume point.
    private var readiness: NSKeyValueObservation?

    /// Plays a recording from its Webex stream.
    ///
    /// - Parameters:
    ///   - stream: What Webex answered, with the HLS address.
    ///   - recording: The recording, for the window's title.
    ///   - cookies: Webex's cookies, sent with the media requests.
    ///   - startAt: Where to start, in seconds, or `nil` for the beginning.
    ///   - onProgress: Hears the position and length every five seconds, and once
    ///     more, marked final, when the window closes.
    func play(
        _ stream: WebexStream, recording: Recording, cookies: [HTTPCookie], startAt: Double? = nil,
        onProgress: @escaping (_ position: Double, _ duration: Double, _ final: Bool) -> Void = { _, _, _ in }
    ) {
        guard let address = stream.hlsURL else { return }
        play(address, recording: recording, cookies: cookies,
             duration: stream.duration.map { Double($0.components.seconds) } ?? 0,
             startAt: startAt, onProgress: onProgress)
    }

    /// Plays a recording from an address: Webex's HLS, or a file saved on the Mac.
    ///
    /// - Parameters:
    ///   - address: What to play.
    ///   - recording: The recording, for the window's title.
    ///   - cookies: Cookies for the media requests; none for a file.
    ///   - duration: The length in seconds when known, until the player measures it.
    ///   - startAt: Where to start, in seconds, or `nil` for the beginning.
    ///   - onProgress: Hears the position and length every five seconds, and once
    ///     more, marked final, when the window closes.
    func play(
        _ address: URL, recording: Recording, cookies: [HTTPCookie] = [], duration: Double = 0,
        startAt: Double? = nil,
        onProgress: @escaping (_ position: Double, _ duration: Double, _ final: Bool) -> Void = { _, _, _ in }
    ) {
        stop()
        let asset = address.isFileURL
            ? AVURLAsset(url: address)
            : AVURLAsset(url: address, options: [AVURLAssetHTTPCookiesKey: cookies])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let fallbackDuration = duration
        self.onProgress = onProgress
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
        ) { [weak self, weak item] time in
            MainActor.assumeIsolated {
                let duration = item?.duration.seconds ?? .nan
                self?.onProgress?(time.seconds, duration.isFinite ? duration : fallbackDuration, false)
            }
        }

        let view = AVPlayerView()
        view.player = player
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = recording.topic ?? recording.form.title
        window.subtitle = recording.courseTitle.capitalized
        window.contentView = view
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        if let startAt, startAt > 0 {
            // A seek before the item is ready is dropped, so wait for it.
            readiness = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.readiness = nil
                    await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
                    player.play()
                }
            }
        } else {
            player.play()
        }
        log.info("Playing transfer \(recording.transferID, privacy: .public)")
    }

    /// Stops whatever is playing, reports where it stopped, and closes the window.
    func stop() {
        if let player {
            player.pause()
            let duration = player.currentItem?.duration.seconds ?? .nan
            onProgress?(player.currentTime().seconds, duration.isFinite ? duration : 0, true)
            if let timeObserver { player.removeTimeObserver(timeObserver) }
        }
        timeObserver = nil
        readiness = nil
        onProgress = nil
        player = nil
        let closing = window
        window = nil
        closing?.delegate = nil
        closing?.close()
    }

    /// Closing the window stops the recording.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard window != nil else { return }
            window?.delegate = nil
            window = nil
            stop()
        }
    }
}
#endif

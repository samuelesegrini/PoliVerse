import Foundation
import OSLog

/// Starts the next queued recording once nothing is downloading.
///
/// The queue itself lives in ``RecordingDownloads``; this is the part that talks to
/// Webex. A queued recording has no address yet — the ninety-minute ticket would
/// expire while it waited — so its turn begins with a fresh one from
/// ``RecordingsModel/freshDownload(for:accountEmail:)``. That needs the Webex session in
/// WebKit, so the queue advances with the app in front: when a download ends there,
/// and each time the app comes back. A download that finished in the background hands
/// over at the next return.
///
/// A recording the lecturer does not allow leaves the queue and the next one goes. A
/// sign-in Webex asks for, or no answer from it, stops the queue where it is.
@MainActor
final class DownloadQueue {
    /// What to do with the head of the queue.
    enum Next: Equatable {
        /// Something is downloading, or nothing is queued.
        case wait
        /// Start this one.
        case start(Int)
        /// Take this one out: its recording is no longer in the list.
        case drop(Int)
    }

    /// `true` while a turn is being set up, so two triggers do not start two downloads.
    private var isAdvancing = false
    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")

    /// What to do with the queue now.
    ///
    /// - Parameters:
    ///   - queue: The queued `transfer_id`s, in order.
    ///   - busy: Whether a download is in flight.
    ///   - known: The queued recordings still in the list.
    /// - Returns: The step.
    nonisolated static func next(queue: [Int], busy: Bool, known: Set<Int>) -> Next {
        guard !busy, let head = queue.first else { return .wait }
        return known.contains(head) ? .start(head) : .drop(head)
    }

    /// Starts queued recordings until one is downloading, the queue is empty, or Webex
    /// asks for a sign-in.
    ///
    /// - Parameters:
    ///   - downloads: The saved recordings and their queue.
    ///   - recordings: The recordings list, and the way to Webex.
    ///   - account: Whose downloads.
    ///   - accountEmail: The student's institutional email, for Webex.
    func advance(downloads: RecordingDownloads, recordings: RecordingsModel,
                 account: any Account, accountEmail: String?) async {
        guard !isAdvancing, !account.isSample, account.matricola != nil else { return }
        isAdvancing = true
        defer { isAdvancing = false }

        while !Task.isCancelled {
            var known = Set<Int>()
            var head: Recording?
            if let first = downloads.queue.first, let recording = await recordings.recording(transferID: first) {
                known.insert(first)
                head = recording
            }
            switch Self.next(queue: downloads.queue, busy: downloads.isBusy, known: known) {
            case .wait:
                return
            case .drop(let id):
                downloads.dequeue(id)
                log.info("Queued transfer \(id, privacy: .public) is no longer in the list; dropped")
            case .start(let id):
                guard let recording = head else { return }
                // Stopped part-way and still resumable: carry on from there, with
                // no request to Webex and nothing downloaded twice.
                if downloads.isResumable(id) {
                    downloads.dequeue(id)
                    if downloads.resume(transferID: id) { return }
                }
                switch await recordings.freshDownload(for: recording, accountEmail: accountEmail) {
                case .ready(let stream, let cookies):
                    // Asking Webex takes a few seconds, and the student may have
                    // started one meanwhile: this one keeps its place for the next
                    // turn rather than making two at once.
                    guard !downloads.isBusy else { return }
                    // Takes it out of the queue, and makes the queue busy.
                    downloads.download(recording, from: stream, cookies: cookies)
                    return
                case .forbidden:
                    downloads.dequeue(id)
                    log.info("Queued transfer \(id, privacy: .public) may not be downloaded; the next goes")
                case .signInNeeded, .noAddress, .noAnswer:
                    // Kept: a sign-in or a moment without Webex is no reason to
                    // forget what the student asked for. Tried again at the next
                    // return, or when the next download ends.
                    log.info("Webex did not give queued transfer \(id, privacy: .public) an address; the queue waits")
                    return
                }
            }
        }
    }
}

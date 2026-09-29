import Foundation
import OSLog

/// Carries on the recording downloads a closed app left behind.
///
/// Force-quitting the app, or iOS reclaiming it, cancels its background downloads;
/// what is left is the data to resume from, good only while the Webex address inside
/// it is — about ninety minutes. Past that, the row used to wait in "interrotto" for
/// a tap. Now, each time the app comes to the front, an interrupted download is
/// resumed when it still can be, and otherwise started again from a fresh address:
/// the old resume data belongs to the old address, so the restart begins from zero.
///
/// One at a time, like every download: the first carries on, and the rest join the
/// queue behind it, where ``DownloadQueue`` resumes each from its saved progress while
/// that is still good.
///
/// Quiet by design. It runs in the foreground only, since a fresh address needs the
/// Webex session in WebKit; it asks nothing of the student; and it stops at the first
/// sign-in Webex asks for, leaving the rest in "interrotto", where the row's menu still
/// offers to resume.
@MainActor
final class DownloadRecovery {
    /// What to do with one interrupted download.
    enum Step: Equatable {
        /// Carry on from the resume data.
        case resume(Int)
        /// Ask Webex for a fresh address and start again.
        case refetch(Int)
        /// Leave it: the recording is not in the list, so there is nothing to ask
        /// Webex about.
        case skip(Int)

        /// The download the step is about, when it is one that can start.
        var id: Int? {
            switch self {
            case .resume(let id), .refetch(let id): id
            case .skip: nil
            }
        }
    }

    /// `true` while a pass runs, so coming to the front twice does not start two.
    private var isRunning = false
    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")

    /// What to do with each interrupted download.
    ///
    /// - Parameters:
    ///   - interrupted: The interrupted downloads, by `transfer_id`.
    ///   - resumable: Those whose resume data is still good.
    ///   - known: Those whose recording is in the list.
    /// - Returns: One step per download, in the order given.
    nonisolated static func plan(interrupted: [Int], resumable: Set<Int>, known: Set<Int>) -> [Step] {
        interrupted.map { id in
            if resumable.contains(id) { return .resume(id) }
            return known.contains(id) ? .refetch(id) : .skip(id)
        }
    }

    /// Carries on every interrupted download it can.
    ///
    /// - Parameters:
    ///   - downloads: The saved recordings.
    ///   - recordings: The recordings list, and the way to Webex.
    ///   - account: Whose downloads.
    ///   - accountEmail: The student's institutional email, for Webex.
    func run(downloads: RecordingDownloads, recordings: RecordingsModel,
             account: any Account, accountEmail: String?) async {
        guard !isRunning, !account.isSample, account.matricola != nil else { return }
        let interrupted = downloads.interrupted
        guard !interrupted.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }

        var held: [Int: Recording] = [:]
        for id in interrupted {
            if let recording = await recordings.recording(transferID: id) { held[id] = recording }
        }
        let steps = Self.plan(interrupted: interrupted,
                              resumable: Set(interrupted.filter(downloads.isResumable)),
                              known: Set(held.keys))
        for step in steps {
            guard !Task.isCancelled else { return }
            // Something is downloading already: this one waits its turn.
            if downloads.isBusy, let recording = step.id.flatMap({ held[$0] }) {
                downloads.enqueue(recording)
                continue
            }
            switch step {
            case .resume(let id):
                downloads.resume(transferID: id)
            case .skip(let id):
                log.info("Interrupted download \(id, privacy: .public) is not in the list; left as it is")
            case .refetch(let id):
                guard let recording = held[id] else { continue }
                switch await recordings.freshDownload(for: recording, accountEmail: accountEmail) {
                case .ready(let stream, let cookies):
                    guard !downloads.isBusy else {
                        downloads.enqueue(recording)
                        continue
                    }
                    downloads.download(recording, from: stream, cookies: cookies)
                    log.info("Interrupted download \(id, privacy: .public) started again from a fresh address")
                case .signInNeeded:
                    // The rest would ask the same; the row's menu is still there.
                    log.info("Webex wants a sign-in; interrupted downloads left for the student")
                    return
                case .forbidden, .noAddress, .noAnswer:
                    log.info("No fresh address for interrupted download \(id, privacy: .public)")
                }
            }
        }
    }
}

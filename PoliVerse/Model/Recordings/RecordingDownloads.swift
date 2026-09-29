import Foundation
import Network
import Observation
import OSLog

/// Lecture recordings saved on the device, for watching without a connection.
///
/// Only when the lecturer allows it — ``WebexStream/allowsDownload`` — and one
/// recording at a time, asked for by the student: the same as the Download button on
/// Webex's page, not a mirror of the archive. See `docs/recordings.md`, "Download".
///
/// A lecture is a couple of hundred megabytes, so it downloads on a background
/// `URLSession` that carries on when the app leaves the screen. The file lands in
/// `Application Support/Recordings/<transfer_id>.mp4`, excluded from backup, and is
/// never offered to share or export: it holds other students' voices. Signing out
/// deletes every file.
///
/// Force-quitting the app cancels its background downloads — iOS does that on
/// purpose, and nothing an app does prevents it. What arrives on the next launch is
/// the cancellation, often with the data to carry on from where it stopped: that is
/// kept beside the file (`<transfer_id>.resume`), and resumed at once while the
/// address inside it is still good — Webex's ticket lasts ninety minutes — or on
/// the student's word, from a fresh address, after that.
@Observable
@MainActor
final class RecordingDownloads {
    /// Where one recording's download stands.
    enum Status: Equatable {
        /// Not on the device, and nothing in flight.
        case idle
        /// Downloading, with the fraction done when known.
        case downloading(Double?)
        /// Stopped part-way — the app was closed — and waiting to be resumed.
        case interrupted
        /// On the device.
        case downloaded(URL)
        /// The download did not complete, with a sentence to show.
        case failed(String)
    }

    /// The one instance, which owns the background session.
    static let shared = RecordingDownloads()

    /// The background session's identifier, which iOS relaunches the app with when
    /// downloads finish while it is not running.
    nonisolated static let sessionIdentifier = "segrini.samuele.PoliVerse.recordings"

    /// Each recording's status, by `transfer_id`. Recordings not listed are idle.
    private(set) var statuses: [Int: Status] = [:]

    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// Receives the session's callbacks off the main actor.
    private let relay: Relay
    /// The background session.
    private let session: URLSession
    /// Called once iOS has delivered every event of a background relaunch.
    private var eventsDelivered: CheckedContinuation<Void, Never>?
    /// The downloads' Live Activities, on the Lock Screen and in the Dynamic Island.
    private let activities = DownloadActivities()

    /// Whether downloads may use cellular data, a personal hotspot, or a connection in
    /// Low Data Mode. On by default; off, a download waits for Wi-Fi.
    ///
    /// A lecture is a couple of hundred megabytes. Changing the choice restarts the
    /// downloads in flight under it, since a request's network rules are fixed when it
    /// is made.
    var allowsCellular: Bool {
        didSet {
            guard allowsCellular != oldValue else { return }
            UserDefaults.standard.set(allowsCellular, forKey: Self.cellularKey)
            restartUnderNetworkChoice()
            refreshWaiting()
        }
    }
    /// Where ``allowsCellular`` is kept.
    nonisolated static let cellularKey = "recordingDownloadsOverCellular"
    /// `true` while a download is held back for Wi-Fi: the only connection is cellular,
    /// a hotspot or in Low Data Mode, and ``allowsCellular`` is off.
    private(set) var isWaitingForWiFi = false
    /// Whether the current connection is one ``allowsCellular`` governs.
    private var onExpensivePath = false
    /// Watches the connection, so a download held back for Wi-Fi says so.
    private let path = NWPathMonitor()

    /// Where the files live.
    nonisolated static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    private init() {
        let relay = Relay()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // The cookies go on the request itself; the session keeps none.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        self.relay = relay
        session = URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
        allowsCellular = UserDefaults.standard.object(forKey: Self.cellularKey) as? Bool ?? true
        relay.owner = self
        path.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.pathChanged(expensive: expensive) }
        }
        path.start(queue: DispatchQueue(label: "segrini.samuele.PoliVerse.recordings-network"))
        scanFiles()
        reattach()
    }

    /// How long after its start a download's resume data is trusted: the life of the
    /// Webex ticket in the address it carries, less a margin.
    private let resumeLifetime: TimeInterval = 80 * 60

    /// When each download in flight was started, by `transfer_id`: the ticket in its
    /// address is that old. Kept across launches, since resuming happens on the next.
    private var startedAt: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: "recordingDownloadStarts") as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "recordingDownloadStarts") }
    }

    /// A recording's status.
    ///
    /// - Parameter recording: The recording.
    /// - Returns: Its status; idle when nothing is known.
    func status(of recording: Recording) -> Status {
        statuses[recording.transferID] ?? .idle
    }

    /// The saved file for a recording, when there is one.
    ///
    /// - Parameter recording: The recording.
    /// - Returns: The file, or `nil`.
    func file(for recording: Recording) -> URL? {
        if case .downloaded(let url) = status(of: recording) { return url }
        return nil
    }

    /// How many recordings of a list are saved.
    ///
    /// - Parameter recordings: The recordings.
    /// - Returns: The number saved on the device.
    func savedCount(in recordings: [Recording]) -> Int {
        recordings.filter { file(for: $0) != nil }.count
    }

    // MARK: - Downloading

    /// Starts downloading a recording from its stream's MP4.
    ///
    /// Does nothing when the stream forbids it, or when the recording is already saved
    /// or downloading.
    ///
    /// - Parameters:
    ///   - recording: The recording.
    ///   - stream: What Webex answered for it, with the MP4 address and the flags.
    ///   - cookies: Webex's cookies, sent along like the player sends them.
    func download(_ recording: Recording, from stream: WebexStream, cookies: [HTTPCookie]) {
        guard stream.allowsDownload, let address = stream.mp4URL else { return }
        dequeue(recording.transferID)
        switch status(of: recording) {
        case .downloading, .downloaded: return
        case .idle, .failed, .interrupted: break
        }
        // A fresh address supersedes what was left of an earlier attempt.
        try? FileManager.default.removeItem(at: Self.resumeFile(for: recording.transferID))
        var request = URLRequest(url: address)
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        Self.apply(allowsCellular, to: &request)
        let task = session.downloadTask(with: request)
        task.taskDescription = String(recording.transferID)
        task.countOfBytesClientExpectsToReceive = Int64(stream.fileSize ?? 0)
        statuses[recording.transferID] = .downloading(nil)
        startedAt[String(recording.transferID)] = .now
        task.resume()
        activities.start(for: recording)
        refreshWaiting()
        log.info("Downloading transfer \(recording.transferID, privacy: .public)")
    }

    /// Carries on an interrupted download from where it stopped, while the address it
    /// was started with is still good.
    ///
    /// - Parameter recording: The recording.
    /// - Returns: Whether it resumed; `false` means it needs a fresh address, through
    ///   ``download(_:from:cookies:)``.
    @discardableResult
    func resume(_ recording: Recording) -> Bool {
        resume(recording.transferID)
    }

    // MARK: - The queue

    /// Recordings the student asked for while another was downloading, by
    /// `transfer_id`, in the order asked. Kept across launches.
    ///
    /// One download at a time, as on Webex's own page: a lecture is a couple of hundred
    /// megabytes, and several at once would each go slower and all finish later. Each
    /// still needs the lecturer's permission, checked when its turn comes, and a fresh
    /// address from Webex, which ``DownloadQueue`` asks for with the app in front.
    private(set) var queue: [Int] = UserDefaults.standard.array(forKey: "recordingDownloadQueue") as? [Int] ?? [] {
        didSet { UserDefaults.standard.set(queue, forKey: "recordingDownloadQueue") }
    }

    /// Whether a download is in flight, so the next asked for waits its turn.
    var isBusy: Bool {
        statuses.values.contains { if case .downloading = $0 { true } else { false } }
    }

    /// Whether a recording is waiting its turn.
    ///
    /// - Parameter recording: The recording.
    /// - Returns: `true` when it is in the queue.
    func isQueued(_ recording: Recording) -> Bool {
        queue.contains(recording.transferID)
    }

    /// Puts a recording at the end of the queue. Does nothing when it is already there,
    /// saved, or downloading.
    ///
    /// - Parameter recording: The recording.
    func enqueue(_ recording: Recording) {
        switch status(of: recording) {
        case .downloading, .downloaded: return
        case .idle, .failed, .interrupted: break
        }
        guard !queue.contains(recording.transferID) else { return }
        queue.append(recording.transferID)
        log.info("Queued transfer \(recording.transferID, privacy: .public), \(self.queue.count, privacy: .public) waiting")
    }

    /// Takes a recording out of the queue.
    ///
    /// - Parameter id: The recording's `transfer_id`.
    func dequeue(_ id: Int) {
        queue.removeAll { $0 == id }
    }

    /// The downloads stopped part-way, waiting to be carried on.
    var interrupted: [Int] {
        statuses.compactMap { id, status in status == .interrupted ? id : nil }.sorted()
    }

    /// Whether an interrupted download can carry on from where it stopped: its resume
    /// data is on the device and the address inside it is still good.
    ///
    /// - Parameter id: The recording's `transfer_id`.
    /// - Returns: `false` when it needs a fresh address.
    func isResumable(_ id: Int) -> Bool {
        guard let started = startedAt[String(id)] else { return false }
        return Date.now.timeIntervalSince(started) < resumeLifetime
            && FileManager.default.fileExists(atPath: Self.resumeFile(for: id).path)
    }

    /// Resumes one download by `transfer_id`, for a recording no longer held in the
    /// list. See ``resume(_:)``.
    @discardableResult
    func resume(transferID id: Int) -> Bool {
        resume(id)
    }

    /// Resumes one download by `transfer_id`. See ``resume(_:)``.
    @discardableResult
    private func resume(_ id: Int) -> Bool {
        let file = Self.resumeFile(for: id)
        guard let started = startedAt[String(id)],
              Date.now.timeIntervalSince(started) < resumeLifetime,
              let data = try? Data(contentsOf: file) else {
            return false
        }
        try? FileManager.default.removeItem(at: file)
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = String(id)
        statuses[id] = .downloading(nil)
        task.resume()
        activities.resumed(id)
        log.info("Resuming download of transfer \(id, privacy: .public)")
        return true
    }

    /// Stops a download in flight.
    ///
    /// - Parameter recording: The recording.
    func cancel(_ recording: Recording) {
        let id = String(recording.transferID)
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
        try? FileManager.default.removeItem(at: Self.resumeFile(for: recording.transferID))
        statuses[recording.transferID] = nil
        activities.dismiss(recording.transferID)
    }

    /// Deletes a saved recording, or what is left of an interrupted download.
    ///
    /// - Parameter recording: The recording.
    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: Self.file(for: recording.transferID))
        try? FileManager.default.removeItem(at: Self.resumeFile(for: recording.transferID))
        statuses[recording.transferID] = nil
        activities.dismiss(recording.transferID)
    }

    /// Deletes every saved recording and stops every download, on sign-out.
    func deleteAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        try? FileManager.default.removeItem(at: Self.directory)
        statuses = [:]
        startedAt = [:]
        queue = []
        activities.dismissAll()
        log.info("Saved recordings deleted")
    }

    // MARK: - The network

    /// Sets a request's network rules from the student's choice.
    ///
    /// - Parameters:
    ///   - cellular: Whether cellular, hotspots and Low Data Mode may be used.
    ///   - request: The request to change.
    nonisolated static func apply(_ cellular: Bool, to request: inout URLRequest) {
        request.allowsExpensiveNetworkAccess = cellular
        request.allowsConstrainedNetworkAccess = cellular
    }

    /// Whether a download is held back: it is in flight, the connection is one the
    /// choice rules out, and the choice rules it out.
    ///
    /// - Parameters:
    ///   - inFlight: Whether any download is in flight.
    ///   - expensive: Whether the connection is cellular, a hotspot or in Low Data Mode.
    ///   - allowsCellular: The student's choice.
    /// - Returns: `true` when downloads are waiting for Wi-Fi.
    nonisolated static func waitsForWiFi(inFlight: Bool, expensive: Bool, allowsCellular: Bool) -> Bool {
        inFlight && expensive && !allowsCellular
    }

    /// Takes a change of connection.
    private func pathChanged(expensive: Bool) {
        onExpensivePath = expensive
        refreshWaiting()
    }

    /// Recomputes ``isWaitingForWiFi`` and tells the Live Activities.
    private func refreshWaiting() {
        let inFlight = statuses.compactMap { id, status -> Int? in
            if case .downloading = status { return id }
            return nil
        }
        let waiting = Self.waitsForWiFi(inFlight: !inFlight.isEmpty, expensive: onExpensivePath,
                                        allowsCellular: allowsCellular)
        guard waiting != isWaitingForWiFi else { return }
        isWaitingForWiFi = waiting
        activities.waiting(inFlight, isWaiting: waiting)
    }

    /// Restarts the downloads in flight whose network rules differ from the choice.
    ///
    /// A request's rules are fixed when it is made, and a download carried on from its
    /// resume data keeps the old request, so each is started again from its original
    /// request with the new rules — from the beginning, within the life of the address.
    private func restartUnderNetworkChoice() {
        let cellular = allowsCellular
        session.getAllTasks { [weak self] tasks in
            let stale = tasks.compactMap { task -> (URLRequest, String)? in
                guard let description = task.taskDescription, Int(description) != nil,
                      var request = task.originalRequest,
                      request.allowsExpensiveNetworkAccess != cellular else { return nil }
                // Renamed first, so its cancellation is not taken for the student's.
                task.taskDescription = "replaced"
                task.cancel()
                Self.apply(cellular, to: &request)
                return (request, description)
            }
            Task { @MainActor in self?.restart(stale) }
        }
    }

    /// Starts again the downloads ``restartUnderNetworkChoice()`` stopped.
    private func restart(_ requests: [(URLRequest, String)]) {
        for (request, description) in requests {
            let task = session.downloadTask(with: request)
            task.taskDescription = description
            task.resume()
            if let id = Int(description) {
                statuses[id] = .downloading(nil)
                activities.resumed(id)
            }
        }
        if !requests.isEmpty { log.info("Restarted \(requests.count, privacy: .public) downloads under the new network choice") }
        refreshWaiting()
    }

    /// Waits until iOS has delivered the events of a background relaunch, so the app
    /// is not suspended before the finished files are moved into place.
    func backgroundEventsDelivered() async {
        await withCheckedContinuation { eventsDelivered = $0 }
    }

    // MARK: - Session events

    /// Takes a download's progress.
    fileprivate func progressed(_ id: Int, fraction: Double?) {
        statuses[id] = .downloading(fraction)
        activities.progressed(id, fraction: fraction)
    }

    /// Takes a download that finished with its file in place.
    fileprivate func finished(_ id: Int, at url: URL) {
        statuses[id] = .downloaded(url)
        startedAt[String(id)] = nil
        activities.ended(id, as: .finished)
        log.info("Downloaded transfer \(id, privacy: .public)")
    }

    /// Takes a download stopped part-way whose resume data has been kept, and carries
    /// it on at once when it still can.
    fileprivate func interrupted(_ id: Int) {
        log.info("Download of transfer \(id, privacy: .public) interrupted")
        if !resume(id) {
            statuses[id] = .interrupted
            activities.ended(id, as: .interrupted)
        }
    }

    /// Takes a download that failed, or was cancelled.
    fileprivate func failed(_ id: Int, message: String?) {
        guard let message else {
            statuses[id] = nil
            activities.dismiss(id)
            return
        }
        statuses[id] = .failed(message)
        activities.ended(id, as: .failed)
        log.error("Download of transfer \(id, privacy: .public) failed: \(message, privacy: .public)")
    }

    /// Takes the end of a background relaunch's events.
    fileprivate func deliveredAll() {
        eventsDelivered?.resume()
        eventsDelivered = nil
    }

    // MARK: - Files

    /// Where a recording's file goes.
    nonisolated static func file(for id: Int) -> URL {
        directory.appending(path: "\(id).mp4")
    }

    /// Where an interrupted download's resume data goes.
    nonisolated static func resumeFile(for id: Int) -> URL {
        directory.appending(path: "\(id).resume")
    }

    /// Marks the files already on the device as downloaded.
    private func scanFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let id = Int(file.deletingPathExtension().lastPathComponent) else { continue }
            switch file.pathExtension {
            case "mp4": statuses[id] = .downloaded(file)
            case "resume" where statuses[id] == nil: statuses[id] = .interrupted
            default: break
            }
        }
    }

    /// Picks up downloads a previous launch left running.
    private func reattach() {
        session.getAllTasks { [weak self] tasks in
            let ids = tasks.compactMap { $0.taskDescription.flatMap(Int.init) }
            Task { @MainActor in
                for id in ids where self?.statuses[id] == nil { self?.statuses[id] = .downloading(nil) }
                // An activity left by a download that is no longer running
                // would show a bar that never moves.
                self?.activities.dismissAll(keeping: Set(ids))
            }
        }
    }
}

/// The background session's delegate, which runs on the session's own queue.
///
/// The finished file must be moved before `didFinishDownloadingTo` returns, so that
/// happens here; everything else is handed to ``RecordingDownloads`` on the main actor.
private final class Relay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// The downloads the events belong to. Set once, before the session starts.
    weak var owner: RecordingDownloads?

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription.flatMap(Int.init) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : downloadTask.countOfBytesClientExpectsToReceive
        let fraction = expected > 0 ? Double(totalBytesWritten) / Double(expected) : nil
        Task { @MainActor [weak owner] in owner?.progressed(id, fraction: fraction.map { min($0, 1) }) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(Int.init) else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let type = response?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // Webex answers an expired ticket with a page, not a video.
        guard let response, (200..<300).contains(response.statusCode), !type.contains("text/html"), size > 1_000_000 else {
            let message = String(localized: "Webex non ha mandato la registrazione. Riprova: il collegamento dura un'ora e mezza.")
            Task { @MainActor [weak owner] in owner?.failed(id, message: message) }
            return
        }
        let destination = RecordingDownloads.file(for: id)
        do {
            try FileManager.default.createDirectory(at: RecordingDownloads.directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = destination
            try? excluded.setResourceValues(values)
            Task { @MainActor [weak owner] in owner?.finished(id, at: destination) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak owner] in owner?.failed(id, message: message) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let id = task.taskDescription.flatMap(Int.init) else { return }
        let info = (error as NSError).userInfo
        // Stopped by the system — the app force-quit, or the connection lost — with
        // the data to carry on: kept, and resumed.
        if let data = info[NSURLSessionDownloadTaskResumeData] as? Data {
            do {
                try FileManager.default.createDirectory(at: RecordingDownloads.directory, withIntermediateDirectories: true)
                try data.write(to: RecordingDownloads.resumeFile(for: id), options: .atomic)
                Task { @MainActor [weak owner] in owner?.interrupted(id) }
                return
            } catch {}
        }
        // A plain cancel is the student's own doing, not a failure to report. One
        // with a system reason and nothing to resume from is a failure.
        let byStudent = (error as NSError).code == NSURLErrorCancelled
            && info[NSURLErrorBackgroundTaskCancelledReasonKey] == nil
        let message = byStudent
            ? nil
            : String(localized: "Il download si è interrotto quando l'app è stata chiusa. Riprova dal menu.")
        Task { @MainActor [weak owner] in owner?.failed(id, message: message) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak owner] in owner?.deliveredAll() }
    }
}

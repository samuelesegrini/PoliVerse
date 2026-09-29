import Foundation
import OSLog
#if os(iOS)
import ActivityKit
#endif

/// Shows each recording's download on the Lock Screen and in the Dynamic Island.
///
/// A lecture is a couple of hundred megabytes and downloads on a background session
/// that carries on with the app closed; the activity is what says so where the student
/// looks. Started when a download starts, fed its progress, and ended a few minutes
/// after it finishes or fails, with the outcome shown until then.
///
/// Progress is published sparingly — see ``DownloadActivityPacing`` — because the
/// system budgets how often an app may update its activities. While the app is
/// suspended no progress arrives at all: the bar holds its last value until iOS wakes
/// the app, which it does when the file is in.
///
/// On the Mac, which has no Live Activities, every call does nothing.
@MainActor
final class DownloadActivities {
    /// The last progress published for each download, by `transfer_id`.
    private var published: [Int: DownloadActivityPacing.Mark] = [:]
    /// How long an outcome stays on screen before the activity dismisses itself.
    nonisolated static let outcomeLifetime: TimeInterval = 5 * 60
    /// Diagnostic log for this type, under the `liveactivity` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "liveactivity")

    /// Starts an activity for a download that has just started. Does nothing when the
    /// student has switched Live Activities off, or one is already showing it.
    ///
    /// - Parameter recording: The recording being downloaded.
    func start(for recording: Recording) {
        #if os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              Self.activity(for: recording.transferID) == nil else { return }
        let attributes = RecordingDownloadAttributes(
            transferID: recording.transferID,
            course: recording.courseTitle,
            detail: Self.detail(of: recording),
            megabytes: recording.megabytes)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(phase: .downloading, fraction: nil), staleDate: nil),
                pushType: nil)
            published[recording.transferID] = DownloadActivityPacing.Mark(fraction: 0, at: .now)
            log.notice("download activity started for transfer \(recording.transferID, privacy: .public)")
        } catch {
            // Too many activities, or the setting switched off meanwhile: the
            // download goes on regardless, and its row still shows it.
            log.error("download activity refused: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Publishes a download's progress, when enough has changed to be worth one of the
    /// system's updates.
    ///
    /// - Parameters:
    ///   - id: The recording's `transfer_id`.
    ///   - fraction: The fraction done, when known.
    func progressed(_ id: Int, fraction: Double?) {
        #if os(iOS)
        guard let fraction,
              DownloadActivityPacing.shouldPublish(fraction, after: published[id], now: .now) else { return }
        published[id] = DownloadActivityPacing.Mark(fraction: fraction, at: .now)
        Task { await Self.update(id, state: .init(phase: .downloading, fraction: fraction)) }
        #endif
    }

    /// Resumes following a download carried on from where it stopped.
    ///
    /// - Parameter id: The recording's `transfer_id`.
    func resumed(_ id: Int) {
        #if os(iOS)
        published[id] = nil
        Task { await Self.update(id, state: .init(phase: .downloading, fraction: nil)) }
        #endif
    }

    /// Shows how a download ended, then lets the activity dismiss itself.
    ///
    /// - Parameters:
    ///   - id: The recording's `transfer_id`.
    ///   - phase: ``RecordingDownloadAttributes/ContentState/Phase/finished``,
    ///     `interrupted` or `failed`.
    func ended(_ id: Int, as phase: RecordingDownloadPhase) {
        #if os(iOS)
        published[id] = nil
        let state = RecordingDownloadAttributes.ContentState(
            phase: phase, fraction: phase == .finished ? 1 : nil)
        Task { await Self.end(id, state: state, after: Self.outcomeLifetime) }
        #endif
    }

    /// Dismisses a download's activity at once: the student cancelled it or deleted the
    /// recording.
    ///
    /// - Parameter id: The recording's `transfer_id`.
    func dismiss(_ id: Int) {
        #if os(iOS)
        published[id] = nil
        Task { await Self.end(id, state: nil, after: 0) }
        #endif
    }

    /// Dismisses every download's activity, on sign-out, and any left over from a
    /// previous launch whose download is no longer running.
    ///
    /// - Parameter keeping: The downloads still in flight, whose activities stay.
    func dismissAll(keeping: Set<Int> = []) {
        #if os(iOS)
        published = published.filter { keeping.contains($0.key) }
        Task { await Self.endAll(keeping: keeping) }
        #endif
    }

    /// `"Lezione · 21 set"`: the kind of session and the day, in Rome.
    ///
    /// - Parameter recording: The recording.
    /// - Returns: The line.
    nonisolated static func detail(of recording: Recording) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: "it_IT"),
                                     timeZone: PoliMiDate.romeCalendar.timeZone)
        let day = recording.recordedAt.formatted(style.day().month(.abbreviated))
        return "\(recording.form.title) · \(day)"
    }

    #if os(iOS)
    // ActivityKit's calls are `nonisolated async` and `Activity` is not
    // `Sendable`, so the lookup and the call both happen outside any actor,
    // as in ``LiveActivityController``.

    /// The activity following a download, if one is showing.
    private nonisolated static func activity(for id: Int) -> Activity<RecordingDownloadAttributes>? {
        Activity<RecordingDownloadAttributes>.activities.first { $0.attributes.transferID == id }
    }

    /// Updates a download's activity.
    private nonisolated static func update(_ id: Int, state: RecordingDownloadAttributes.ContentState) async {
        guard let live = activity(for: id) else { return }
        await live.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Ends a download's activity, showing a last state for a while when given one.
    private nonisolated static func end(_ id: Int, state: RecordingDownloadAttributes.ContentState?,
                                        after lifetime: TimeInterval) async {
        guard let live = activity(for: id) else { return }
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        await live.end(content, dismissalPolicy: lifetime > 0 ? .after(.now.addingTimeInterval(lifetime)) : .immediate)
    }

    /// Ends every download's activity but those given.
    private nonisolated static func endAll(keeping: Set<Int>) async {
        for live in Activity<RecordingDownloadAttributes>.activities
        where !keeping.contains(live.attributes.transferID) {
            await live.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}

#if os(iOS)
/// How a download ended, as its activity says it.
typealias RecordingDownloadPhase = RecordingDownloadAttributes.ContentState.Phase
#else
/// How a download ended. The Mac has no Live Activities; the type keeps the callers
/// the same on both.
enum RecordingDownloadPhase {
    case downloading, finished, interrupted, failed
}
#endif

/// When a download's progress is worth publishing.
///
/// The system budgets an app's activity updates, and one per `didWriteData` — dozens a
/// second — would spend the budget in moments and leave the bar frozen. A change is
/// published when it has moved at least two points and a second has passed since the
/// last, and always when the download reaches the end.
nonisolated enum DownloadActivityPacing {
    /// What was last published.
    struct Mark: Sendable, Equatable {
        /// The fraction shown.
        let fraction: Double
        /// When.
        let at: Date
    }

    /// The smallest step worth showing.
    static let step = 0.02
    /// The shortest time between two updates.
    static let interval: TimeInterval = 1

    /// Whether a fraction should be published.
    ///
    /// - Parameters:
    ///   - fraction: The fraction done now.
    ///   - last: What was last published, if anything.
    ///   - now: The clock.
    /// - Returns: `true` when it should.
    static func shouldPublish(_ fraction: Double, after last: Mark?, now: Date) -> Bool {
        guard let last else { return true }
        if fraction >= 1 { return last.fraction < 1 }
        return fraction - last.fraction >= step && now.timeIntervalSince(last.at) >= interval
    }
}

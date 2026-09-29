import Foundation
import Testing
@testable import PoliVerse

/// When a download's Live Activity is updated, and what it says about the lecture.
///
/// The system budgets an app's activity updates: publishing every
/// `didWriteData` would spend it in seconds and freeze the bar.
@Suite("Download activity")
struct DownloadActivityTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("The first figure is always published")
    func first() {
        #expect(DownloadActivityPacing.shouldPublish(0.001, after: nil, now: now))
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let label: String
        let fraction: Double
        let seconds: TimeInterval
        let expected: Bool
        var testDescription: String { label }
    }

    @Test("Progress goes out in steps of two points, at most once a second", arguments: [
        Case(label: "a small step, soon", fraction: 0.405, seconds: 0.2, expected: false),
        Case(label: "a small step, later", fraction: 0.41, seconds: 5, expected: false),
        Case(label: "a big step, soon", fraction: 0.5, seconds: 0.2, expected: false),
        Case(label: "a big step, later", fraction: 0.43, seconds: 1.5, expected: true),
        Case(label: "the end, at once", fraction: 1, seconds: 0.1, expected: true),
    ])
    func pacing(_ step: Case) {
        let last = DownloadActivityPacing.Mark(fraction: 0.40, at: now)
        #expect(DownloadActivityPacing.shouldPublish(step.fraction, after: last,
                                                     now: now.addingTimeInterval(step.seconds)) == step.expected)
    }

    @Test("The end is published once")
    func endOnce() {
        let done = DownloadActivityPacing.Mark(fraction: 1, at: now)
        #expect(!DownloadActivityPacing.shouldPublish(1, after: done, now: now.addingTimeInterval(10)))
    }

    @Test("The detail line names the kind of session and the day, in Italian")
    func detail() {
        let recordedAt = PoliMiDate.romeCalendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 10))!
        let recording = Recording(transferID: 1, academicYear: "2026/27", recordedAt: recordedAt,
                                  teachingCode: "090950", courseTitle: "Sistemi Distribuiti", lecturer: nil,
                                  form: .lecture, topic: nil, minutes: 90, megabytes: 180)
        #expect(DownloadActivities.detail(of: recording) == "Lezione · 21 set")
    }
}

/// When a recording's download waits for Wi-Fi, and what its request allows.
@Suite("Download network choice")
struct DownloadNetworkTests {
    @Test("A download waits for Wi-Fi only on cellular, with cellular turned off", arguments: [
        (true, true, false, true),
        (true, true, true, false),
        (true, false, false, false),
        (false, true, false, false),
    ])
    func waits(inFlight: Bool, expensive: Bool, allowsCellular: Bool, expected: Bool) {
        #expect(RecordingDownloads.waitsForWiFi(inFlight: inFlight, expensive: expensive,
                                                allowsCellular: allowsCellular) == expected)
    }

    @Test("The choice sets both the cellular and the Low Data Mode rules")
    func request() {
        var request = URLRequest(url: URL(string: "https://example.com/lecture.mp4")!)
        RecordingDownloads.apply(false, to: &request)
        #expect(!request.allowsExpensiveNetworkAccess)
        #expect(!request.allowsConstrainedNetworkAccess)
        RecordingDownloads.apply(true, to: &request)
        #expect(request.allowsExpensiveNetworkAccess)
        #expect(request.allowsConstrainedNetworkAccess)
    }
}

/// Carrying on the downloads a closed app left behind.
@Suite("Download recovery")
struct DownloadRecoveryTests {
    /// Resume data still good wins: it carries on from where it stopped, with no
    /// request to Webex. Past that, a recording in the list is asked for afresh;
    /// one that is not cannot be, and is left for the student.
    @Test("Each interrupted download resumes, is asked for afresh, or is left")
    func plan() {
        let steps = DownloadRecovery.plan(interrupted: [1, 2, 3, 4], resumable: [1, 4], known: [1, 2])
        #expect(steps == [.resume(1), .refetch(2), .skip(3), .resume(4)])
    }

    @Test("Nothing interrupted, nothing to do")
    func empty() {
        #expect(DownloadRecovery.plan(interrupted: [], resumable: [], known: []).isEmpty)
    }
}

import Foundation
import Testing
@testable import PoliVerse

/// The student's own notification hours, and WeBeep news switched off on its
/// own.
@Suite("Quiet hours and WeBeep switch")
struct QuietHoursTests {
    private let day = Date(timeIntervalSince1970: 1_772_000_000)

    private func update(_ kind: ExamUpdate.Kind, source: ExamUpdate.Source = .exams, at hour: Int) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: 1, courseCode: "097785", courseName: "Basi di Dati",
                   detectedAt: PoliMiDate.time(hour, on: day), source: source, evidence: "t",
                   newValue: "B.3.2", wasEnrolled: true, examDate: PoliMiDate.time(9, on: day.addingTimeInterval(4 * 86400)))
    }

    private func decide(_ update: ExamUpdate, _ preferences: NotificationPreferences) -> ExamUpdate.Delivery? {
        ExamUpdatePolicy.decide([update], history: [], preferences: preferences, now: update.detectedAt).first?.delivery
    }

    @Test("Quiet hours follow the student's choice")
    func customQuiet() {
        var preferences = NotificationPreferences()
        preferences.quietFrom = 21
        preferences.quietUntil = 9
        #expect(decide(update(.roomChanged, at: 22), preferences) == .morning)
        #expect(decide(update(.roomChanged, at: 8), preferences) == .morning)
        #expect(decide(update(.roomChanged, at: 10), preferences) == .priority)
        // Urgent still goes through.
        #expect(decide(update(.gradePublished, at: 22), preferences) == .urgent)
    }

    @Test("The same start and end hour means no quiet hours")
    func noQuiet() {
        var preferences = NotificationPreferences()
        preferences.quietFrom = 0
        preferences.quietUntil = 0
        #expect(decide(update(.roomChanged, at: 3), preferences) == .priority)
    }

    @Test("Held updates go out at the end of the student's quiet hours")
    func morningAtChosenHour() {
        var held = update(.roomChanged, at: 22)
        held.delivery = .morning
        var preferences = NotificationPreferences()
        preferences.quietUntil = 9
        let digests = ExamUpdatePolicy.digests(from: [held], now: held.detectedAt, preferences: preferences)
        #expect(digests.first?.fireDate == PoliMiDate.time(9, on: day.addingTimeInterval(86400)))
    }

    @Test("WeBeep news can be switched off on its own")
    func weBeepOff() {
        var preferences = NotificationPreferences()
        preferences.weBeepUpdates = false
        var results = update(.resultsPosted, source: .webeep, at: 12)
        results.lookup = ResultsLookup(looksLikeResults: true, found: true, grade: "27")
        #expect(decide(results, preferences) == .inApp)
        #expect(decide(update(.gradePublished, at: 12), preferences) == .urgent)
    }

    @Test("Older stored preferences keep the default hours and WeBeep on")
    func legacy() throws {
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"lectures":true}"#.utf8))
        #expect(decoded.quietFrom == 23)
        #expect(decoded.quietUntil == 7)
        #expect(decoded.weBeepUpdates)
    }

    @Test("Quiet hours within one day, not across midnight")
    func sameDayQuiet() {
        var preferences = NotificationPreferences()
        preferences.quietFrom = 1
        preferences.quietUntil = 6
        #expect(preferences.isQuiet(hour: 3))
        #expect(!preferences.isQuiet(hour: 0))
        #expect(!preferences.isQuiet(hour: 6))
        #expect(decide(update(.roomChanged, at: 0), preferences) == .priority)
    }

    /// §11.3: nothing non-urgent goes out during quiet hours, the evening
    /// summary included.
    @Test("An evening summary that falls in quiet hours waits for their end")
    func eveningInQuiet() {
        var preferences = NotificationPreferences()
        preferences.quietFrom = 17
        preferences.quietUntil = 9
        var held = update(.enrolmentOpened, at: 12)
        held.delivery = .digest
        let digests = ExamUpdatePolicy.digests(from: [held], now: held.detectedAt, preferences: preferences)
        #expect(digests.first?.fireDate == PoliMiDate.time(9, on: day.addingTimeInterval(86400)))
    }
}

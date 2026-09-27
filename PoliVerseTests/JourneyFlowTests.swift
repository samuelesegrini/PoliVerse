import Foundation
import Testing
@testable import PoliVerse

/// The journey asks what the app is for before it asks for the account, and every
/// later step reads those answers. Getting the order wrong puts the login back in
/// front of the student; getting the answers wrong switches on reminders nobody
/// asked for, or moves Oggi around for no reason.
@Suite("Journey flow")
struct JourneyFlowTests {
    @Test("The questions and the preview come before the account")
    func accountIsFourth() {
        let steps = JourneyFlow.steps(in: .init())
        #expect(steps.prefix(4) == [.welcome, .intents, .preview, .signIn])
    }

    @Test("The last step is always the one that opens the app")
    func endsAtReady() {
        #expect(JourneyFlow.steps(in: .init()).last == .ready)
        #expect(JourneyFlow.steps(in: .init(isSignedIn: true)).last == .ready)
        #expect(JourneyFlow.steps(in: .init(isDemo: true)).last == .ready)
    }

    /// The app schedules nothing from invented lectures, and iOS never asks twice.
    @Test("Reminders are skipped for the sample data and after a refusal")
    func remindersOnlyWhenTheyCanWork() {
        #expect(JourneyFlow.steps(in: .init(isSignedIn: true)).contains(.reminders))
        #expect(!JourneyFlow.steps(in: .init(isSignedIn: true, isDemo: true)).contains(.reminders))
        #expect(!JourneyFlow.steps(in: .init(isSignedIn: true, notificationsDenied: true)).contains(.reminders))
    }

    @Test("Signing in moves the journey on to the studies, then the reminders")
    func signInLeadsToStudies() {
        #expect(JourneyFlow.next(after: .signIn, in: .init(isSignedIn: true)) == .studies)
        #expect(JourneyFlow.next(after: .signIn, in: .init(isSignedIn: true, isDemo: true)) == .studies)
        #expect(JourneyFlow.next(after: .studies, in: .init(isSignedIn: true)) == .reminders)
        #expect(JourneyFlow.next(after: .studies, in: .init(isSignedIn: true, isDemo: true)) == .atmosphere)
    }

    /// Signing in again over a live session has the identity provider replay the
    /// grant, so the account step is behind a one-way door once passed.
    @Test("No way back onto the sign-in once there is a session")
    func noBackOntoSignIn() {
        #expect(!JourneyFlow.canGoBack(from: .studies, in: .init(isSignedIn: true)))
        #expect(!JourneyFlow.canGoBack(from: .studies, in: .init(isSignedIn: true, isDemo: true)))
        #expect(JourneyFlow.canGoBack(from: .reminders, in: .init(isSignedIn: true)))
        #expect(JourneyFlow.canGoBack(from: .preview, in: .init()))
        #expect(JourneyFlow.canGoBack(from: .signIn, in: .init()))
    }

    @Test("Nothing goes back from the welcome, or from the last card")
    func noBackAtTheEnds() {
        #expect(!JourneyFlow.canGoBack(from: .welcome, in: .init()))
        #expect(!JourneyFlow.canGoBack(from: .ready, in: .init(isSignedIn: true)))
    }

    @Test("A step that stopped applying falls forward")
    func fallsForward() {
        #expect(JourneyFlow.next(after: .reminders, in: .init(isSignedIn: true, isDemo: true)) == .atmosphere)
    }

    // MARK: - Answers

    @Test("No answer, and «Boh… per Tutto», both stand for every answer")
    func everythingExpands() {
        #expect(JourneyFlow.expanded([]) == JourneyFlow.Intent.concrete)
        #expect(JourneyFlow.expanded([.everything]) == JourneyFlow.Intent.concrete)
        #expect(JourneyFlow.expanded([.exams, .timetable]) == [.timetable, .exams])
    }

    /// Only answers Oggi has a section for move it; the rest live in their tabs.
    @Test("Answers lift their Oggi sections, in order")
    func leadingSections() {
        #expect(JourneyFlow.leadingSections(for: [.timetable]) == [.currentClass, .timetable])
        #expect(JourneyFlow.leadingSections(for: [.exams, .timetable]) == [.currentClass, .timetable, .exams])
        #expect(JourneyFlow.leadingSections(for: [.rooms, .average]).isEmpty)
    }

    @Test("Reminders start on for what was asked for, and off for the rest")
    func remindersFollowAnswers() {
        let rooms = JourneyFlow.reminders(for: [.rooms])
        #expect(!rooms.lectures && !rooms.exams && !rooms.weBeep)
        let average = JourneyFlow.reminders(for: [.average])
        #expect(average.exams && !average.lectures)
        let everything = JourneyFlow.reminders(for: [.everything])
        #expect(everything.lectures && everything.exams && everything.weBeep)
    }

    @Test("Reminder groups write every switch they stand for, and nothing else")
    func reminderGroupsApply() {
        var preferences = NotificationPreferences()
        preferences.leadMinutes = 30
        JourneyFlow.ReminderGroups(lectures: false, exams: true, weBeep: false).apply(to: &preferences)
        #expect(!preferences.lectures)
        #expect(preferences.exams && preferences.enrolments && preferences.examUpdates)
        #expect(!preferences.weBeepUpdates && !preferences.deadlines)
        #expect(preferences.leadMinutes == 30)
    }

    @Test("WeBeep is offered only to someone who came for the recordings")
    func weBeepOffer() {
        #expect(JourneyFlow.offersWeBeep(for: [.recordings]))
        #expect(JourneyFlow.offersWeBeep(for: [.everything]))
        #expect(!JourneyFlow.offersWeBeep(for: [.timetable, .exams]))
    }

    @Test("Leading a look puts the sections first, shown, without losing the others")
    func lookLeads() {
        var style = TodayStyle()
        let before = Set(style.sections.map(\.kind))
        style.lead(with: [.currentClass, .timetable, .exams])
        #expect(Array(style.visibleSections.prefix(3).map(\.kind)) == [.currentClass, .timetable, .exams])
        #expect(before.isSubset(of: Set(style.sections.map(\.kind))))
    }
}

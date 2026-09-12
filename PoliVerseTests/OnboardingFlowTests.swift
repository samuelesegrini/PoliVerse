import Foundation
import Testing
@testable import PoliVerse

/// The onboarding is a sequence whose shape depends on the account behind it:
/// one career or three, WeBeep already connected or not, notifications the
/// user has already refused. Getting that wrong is not a cosmetic bug — it is
/// asking someone to choose a career they do not have, or re-requesting a
/// permission iOS will never grant again.
@Suite("Onboarding flow")
struct OnboardingFlowTests {
    @Test("A fresh install starts at the welcome")
    func startsAtWelcome() {
        #expect(OnboardingFlow.steps(in: .init()).first == .welcome)
    }

    @Test("Signing in is the second step, before anything that needs an account")
    func signInComesSecond() {
        let steps = OnboardingFlow.steps(in: .init())
        #expect(steps.prefix(2) == [.welcome, .signIn])
    }

    /// Everything after the sign-in reads the account, so nothing may precede
    /// it that would show empty.
    @Test("Every account-dependent step follows the sign-in")
    func accountStepsFollowSignIn() {
        let steps = OnboardingFlow.steps(
            in: .init(isSignedIn: true, hasCareerChoice: true))
        let signIn = steps.firstIndex(of: .signIn)!
        for step in [OnboardingFlow.Step.reminders, .career, .weBeep] {
            #expect(steps.firstIndex(of: step)! > signIn)
        }
    }

    @Test("The last step is always the finish")
    func endsAtReady() {
        #expect(OnboardingFlow.steps(in: .init()).last == .ready)
        #expect(OnboardingFlow.steps(in: .init(isSignedIn: true)).last == .ready)
        #expect(OnboardingFlow.steps(in: .init(isDemo: true)).last == .ready)
    }

    /// Sample data needs no account, no career and no WeBeep, and the app
    /// deliberately schedules no reminders from it — so offering any of those
    /// would be offering something that does nothing.
    @Test("Sample data skips the sign-in and everything that depends on it")
    func demoSkipsAccountSteps() {
        #expect(OnboardingFlow.steps(in: .init(isDemo: true)) == [.welcome, .ready])
    }

    @Test("One career means no career step")
    func singleCareerSkipsChoice() {
        let steps = OnboardingFlow.steps(in: .init(isSignedIn: true, hasCareerChoice: false))
        #expect(!steps.contains(.career))
    }

    @Test("More than one career asks which")
    func severalCareersAsk() {
        let steps = OnboardingFlow.steps(in: .init(isSignedIn: true, hasCareerChoice: true))
        #expect(steps.contains(.career))
    }

    @Test("WeBeep already connected is not asked for again")
    func connectedWeBeepSkipped() {
        let steps = OnboardingFlow.steps(
            in: .init(isSignedIn: true, isWeBeepConnected: true))
        #expect(!steps.contains(.weBeep))
    }

    /// iOS remembers a refusal and will never show the prompt again, so a
    /// step whose whole purpose is to ask would be a dead end.
    @Test("Notifications already refused are not asked for again")
    func deniedNotificationsSkipped() {
        let steps = OnboardingFlow.steps(
            in: .init(isSignedIn: true, notificationsDenied: true))
        #expect(!steps.contains(.reminders))
    }

    @Test("The step after the welcome is the sign-in")
    func advancesFromWelcome() {
        #expect(OnboardingFlow.next(after: .welcome, in: .init()) == .signIn)
    }

    @Test("The finish has nothing after it")
    func readyIsTerminal() {
        #expect(OnboardingFlow.next(after: .ready, in: .init()) == nil)
    }

    /// The context changes underneath the flow: the sign-in step is what makes
    /// `isSignedIn` true, and the career count is only known afterwards. The
    /// next step must therefore be computed from the context as it is *now*,
    /// not from a list built at the start.
    @Test("Signing in during the flow opens the steps that needed an account")
    func contextChangesMidFlow() {
        let after = OnboardingFlow.next(
            after: .signIn, in: .init(isSignedIn: true, hasCareerChoice: true))
        #expect(after == .reminders)
    }

    @Test("A step no longer in the sequence still advances to the next one that is")
    func skipsVanishedSteps() {
        // Reminders refused and no career choice: from the sign-in the only
        // thing left to offer is WeBeep.
        let after = OnboardingFlow.next(
            after: .signIn,
            in: .init(isSignedIn: true, hasCareerChoice: false, notificationsDenied: true))
        #expect(after == .weBeep)
    }

    @Test("Choosing sample data at the welcome goes straight to the finish")
    func demoAdvancesToReady() {
        #expect(OnboardingFlow.next(after: .welcome, in: .init(isDemo: true)) == .ready)
    }
}

/// The cursor over the flow, and the one fact that outlives the launch.
@Suite("Onboarding state")
@MainActor
struct OnboardingStateTests {
    /// A suite of its own per test, so nothing here can read or write the
    /// real install's answer.
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "onboarding-tests-\(UUID().uuidString)")!
    }

    @Test("A fresh install has not been through it")
    func freshInstallIsIncomplete() {
        #expect(!OnboardingState(defaults: defaults()).isComplete)
    }

    @Test("Advancing walks the steps that apply")
    func advanceWalksSteps() {
        let state = OnboardingState(defaults: defaults())
        let context = OnboardingFlow.Context(isSignedIn: true)
        state.advance(in: context)
        #expect(state.step == .signIn)
        state.advance(in: context)
        #expect(state.step == .reminders)
    }

    @Test("Advancing past the last step finishes")
    func advancePastEndCompletes() {
        let state = OnboardingState(defaults: defaults())
        state.advance(in: .init(isDemo: true))
        #expect(state.step == .ready)
        state.advance(in: .init(isDemo: true))
        #expect(state.isComplete)
    }

    /// Signing out to switch career must not put anyone back through the
    /// tour, so this is remembered per install rather than per account.
    @Test("Completion survives a new instance")
    func completionPersists() {
        let defaults = defaults()
        OnboardingState(defaults: defaults).complete()
        #expect(OnboardingState(defaults: defaults).isComplete)
    }

    @Test("Restarting puts it back at the welcome")
    func restartReturnsToWelcome() {
        let defaults = defaults()
        let state = OnboardingState(defaults: defaults)
        state.complete()
        state.restart()
        #expect(state.step == .welcome)
        #expect(!state.isComplete)
        #expect(!OnboardingState(defaults: defaults).isComplete)
    }
}

/// Upgrading is the case that hurts: the completion flag is absent on every
/// install that predates onboarding, and treating that as a first run would
/// hand a tour to a student who has been using the app all term.
@Suite("Onboarding on an existing install")
@MainActor
struct OnboardingAdoptionTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "onboarding-adopt-\(UUID().uuidString)")!
    }

    @Test("A restored session at launch counts as having been through it")
    func restoredSessionAdopts() {
        let state = OnboardingState(defaults: defaults())
        state.adoptExistingInstall()
        #expect(state.isComplete)
    }

    /// The signal is "signed in *before* the flow asked anyone to sign in".
    /// Once past the welcome, a token is this flow's own doing.
    @Test("A sign-in from inside the flow does not end it early")
    func midFlowSignInDoesNotAdopt() {
        let state = OnboardingState(defaults: defaults())
        state.advance(in: .init())
        #expect(state.step == .signIn)
        state.adoptExistingInstall()
        #expect(!state.isComplete)
    }

    /// "Rivedi l'introduzione" puts a signed-in student back at `.welcome`,
    /// which is exactly the shape the adoption looks for. Without the
    /// once-per-launch latch the button would close the tour as fast as it
    /// opened it.
    @Test("Re-running the tour from Settings is not undone by the launch check")
    func restartSurvivesAdoption() {
        let state = OnboardingState(defaults: defaults())
        state.adoptExistingInstall()
        state.restart()
        state.adoptExistingInstall()
        #expect(!state.isComplete)
        #expect(state.step == .welcome)
    }
}

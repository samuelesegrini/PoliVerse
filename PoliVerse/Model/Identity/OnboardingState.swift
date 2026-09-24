import Foundation
import Observation

/// The cursor over ``OnboardingFlow``, and the record that the first run has
/// happened.
///
/// ``OnboardingFlow`` is the pure sequence; this holds the current ``step``, which
/// direction the last move went, and the one fact that outlives the launch —
/// ``isComplete``.
///
/// Kept out of ``Session`` deliberately: completion is true of the install rather
/// than of the account, so signing out to switch career does not put a student
/// back through the tour.
@MainActor
@Observable
final class OnboardingState {
    /// Defaults key for ``isComplete``.
    private static let completedKey = "hasCompletedOnboarding"

    /// The step currently on screen.
    private(set) var step: OnboardingFlow.Step = .welcome
    /// Whether the first run has been finished. Restored from `UserDefaults` at init.
    private(set) var isComplete: Bool

    /// Which direction the last move went, so the transition can play the right way.
    ///
    /// Recorded where the move is made rather than inferred in the view by comparing
    /// two step values.
    private(set) var isMovingBack = false

    /// The step of ``JourneyFlow`` on screen: the first run the app now shows.
    ///
    /// Held here rather than in the view, like ``step``, because signing in swaps the
    /// view out from under it.
    private(set) var journeyStep: JourneyFlow.Step = .welcome

    /// What the student said the app is for, on ``JourneyFlow/Step/intents``.
    var intents: Set<JourneyFlow.Intent> = [.timetable, .exams, .recordings]

    /// Whether the journey's sign-in step should open the ways in by itself: set
    /// when the career sheet signs out to move to another matricola.
    var reopensSignIn = false

    /// Whether ``RootView`` should draw the app underneath the journey, so pulling the
    /// last card down reveals it.
    var revealsApp: Bool { !isComplete && journeyStep == .ready }

    /// Where ``isComplete`` is persisted.
    private let defaults: UserDefaults

    /// Reads whether the first run has already happened.
    ///
    /// - Parameter defaults: Where the completion flag is stored.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isComplete = defaults.bool(forKey: Self.completedKey)
    }

    /// Moves to the next step that applies, or completes the flow when none does.
    ///
    /// The context is passed at each call rather than held, because it changes during
    /// the flow: the sign-in step is what makes the session exist, and how many careers
    /// there are is only known after it.
    ///
    /// - Parameter context: What the flow should take into account now.
    func advance(in context: OnboardingFlow.Context) {
        guard let next = OnboardingFlow.next(after: step, in: context) else {
            complete()
            return
        }
        isMovingBack = false
        step = next
    }

    /// Steps back, where the flow allows it. Does nothing otherwise.
    ///
    /// - Parameter context: What the flow should take into account now.
    func goBack(in context: OnboardingFlow.Context) {
        guard OnboardingFlow.canGoBack(from: step, in: context),
              let previous = OnboardingFlow.previous(before: step, in: context)
        else { return }
        isMovingBack = true
        step = previous
    }

    /// Ends the flow for good, from wherever it has reached, and records it.
    ///
    /// Nothing returns a student to the flow on its own; every setting it collects is
    /// reachable from Impostazioni afterwards. ``replay()`` is the one way back in.
    func complete() {
        isComplete = true
        defaults.set(true, forKey: Self.completedKey)
    }

    /// Runs the flow again from the welcome, at the student's request.
    ///
    /// In memory only: the stored flag stays set, so quitting halfway through a replay
    /// opens the app as usual next time.
    func replay() {
        isMovingBack = false
        step = .welcome
        journeyStep = .welcome
        isComplete = false
    }

    // MARK: - Journey

    /// Moves the journey to the next step that applies, or completes it.
    ///
    /// - Parameter context: What the journey should take into account now.
    func advanceJourney(in context: JourneyFlow.Context) {
        guard let next = JourneyFlow.next(after: journeyStep, in: context) else {
            complete()
            return
        }
        isMovingBack = false
        journeyStep = next
    }

    /// Steps the journey back, where it allows it.
    ///
    /// - Parameter context: What the journey should take into account now.
    func goBackInJourney(in context: JourneyFlow.Context) {
        guard JourneyFlow.canGoBack(from: journeyStep, in: context),
              let previous = JourneyFlow.previous(before: journeyStep, in: context)
        else { return }
        isMovingBack = true
        journeyStep = previous
    }

    /// Jumps straight to a step: the welcome's "Ho già un account" goes to the
    /// sign-in without the questions.
    ///
    /// - Parameter step: Where to go.
    func jumpJourney(to step: JourneyFlow.Step) {
        isMovingBack = false
        journeyStep = step
    }
}

/// Upgrade handling for installs that predate the first-run flow.
extension OnboardingState {
    /// Marks an install that plainly predates the first-run flow as having completed
    /// it.
    ///
    /// The completion flag is absent on every install that upgraded into this version,
    /// so without this a student with a term's worth of data would be handed a welcome
    /// tour. A restored session proves the app has been used, and cannot be confused
    /// with a genuine first run: a new student reaches the sign-in step before a token
    /// exists, so still being at the welcome with a live session means the session came
    /// from the Keychain.
    ///
    /// Does nothing once the flow is complete, or past the welcome.
    func adoptExistingInstall() {
        guard !isComplete, step == .welcome, journeyStep == .welcome else { return }
        complete()
    }
}

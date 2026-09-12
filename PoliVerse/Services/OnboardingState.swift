import Foundation
import Observation

/// Where the first run has got to, and whether it has happened at all.
///
/// Separate from ``OnboardingFlow``, which is the pure sequence: this is the
/// cursor over it, plus the one fact that has to outlive the launch — that the
/// student has been through it. Kept out of ``Session`` on purpose, because it
/// is true of the *install*, not of the account: signing out to switch career
/// must not put someone back through the tour.
@MainActor
@Observable
final class OnboardingState {
    private static let completedKey = "hasCompletedOnboarding"

    private(set) var step: OnboardingFlow.Step = .welcome
    private(set) var isComplete: Bool

    private let defaults: UserDefaults
    /// Whether the launch check below has already had its one chance.
    private var hasConsideredLaunch = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isComplete = defaults.bool(forKey: Self.completedKey)
    }

    /// Moves to the next step that applies, or finishes.
    ///
    /// The context is passed in at each call rather than held, because it
    /// changes *during* the flow: the sign-in step is what makes `isSignedIn`
    /// true, and how many careers there are is only known after it.
    func advance(in context: OnboardingFlow.Context) {
        guard let next = OnboardingFlow.next(after: step, in: context) else {
            complete()
            return
        }
        step = next
    }

    /// Ends the flow, from wherever it is. Every step past the sign-in is
    /// skippable, and "più tardi" has to mean it.
    func complete() {
        isComplete = true
        defaults.set(true, forKey: Self.completedKey)
    }

    /// Runs the flow again from the top, for the button in Settings. Does not
    /// sign anyone out: a second pass is for reading, and for the settings it
    /// collects.
    func restart() {
        step = .welcome
        isComplete = false
        defaults.set(false, forKey: Self.completedKey)
    }
}

extension OnboardingState {
    /// Marks an install that plainly predates the onboarding as having done it.
    ///
    /// The completion flag is absent on every install that upgraded into this
    /// version, so without this an existing student — signed in, with a term's
    /// worth of data — would be handed a welcome tour on launch and asked to
    /// sign in again. A restored session is proof the app has been used, and
    /// the only moment it can be confused with a genuine first run is never:
    /// a new student reaches the sign-in step before a token exists, so being
    /// still at `.welcome` with a live session means the session came from the
    /// Keychain rather than from this flow.
    ///
    /// Acts once per launch. "Rivedi l'introduzione" in Settings also puts the
    /// flow back to `.welcome` with a live session, and without the latch this
    /// would close it again the instant it opened.
    func adoptExistingInstall() {
        guard !hasConsideredLaunch else { return }
        hasConsideredLaunch = true
        guard !isComplete, step == .welcome else { return }
        complete()
    }
}

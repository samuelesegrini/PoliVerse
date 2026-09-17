import Foundation

/// Which steps the first run is made of, and in what order.
///
/// Kept apart from the views because the sequence is not fixed: it depends on
/// the account behind it, and the account is not known until halfway through.
/// A student with one enrolment must not be asked which career to use; one who
/// has already refused notifications must not be shown a button that asks iOS
/// for a permission it will never prompt for again; someone exploring the
/// sample data has no account at all and nothing that reads one applies.
///
/// So the sequence is **derived, never stored**. `next(after:)` asks what the
/// context is now rather than walking a list built at the start, because the
/// sign-in step is precisely what changes that context.
nonisolated enum OnboardingFlow {
    enum Step: String, CaseIterable, Identifiable, Sendable {
        /// What the app is, before asking for anything.
        case welcome
        /// The Politecnico's own login page.
        case signIn
        /// Permission, and how far ahead to be told.
        case reminders
        /// Which enrolment, when there is more than one.
        case career
        /// The course materials, which sign in separately.
        case weBeep
        /// What was set up, and where to change it later.
        case ready

        var id: String { rawValue }
    }

    /// What the flow knows about the account at this moment.
    struct Context: Equatable, Sendable {
        var isSignedIn = false
        /// The student chose to explore the sample data instead of signing in.
        var isDemo = false
        var hasCareerChoice = false
        var isWeBeepConnected = false
        /// iOS has been asked once and told no. Asking again does nothing.
        var notificationsDenied = false

        init(
            isSignedIn: Bool = false,
            isDemo: Bool = false,
            hasCareerChoice: Bool = false,
            isWeBeepConnected: Bool = false,
            notificationsDenied: Bool = false
        ) {
            self.isSignedIn = isSignedIn
            self.isDemo = isDemo
            self.hasCareerChoice = hasCareerChoice
            self.isWeBeepConnected = isWeBeepConnected
            self.notificationsDenied = notificationsDenied
        }
    }

    /// The steps that apply, in order.
    static func steps(in context: Context) -> [Step] {
        // Sample data needs no account, no career and no WeBeep, and the app
        // deliberately schedules nothing from it — every other step would be
        // offering something that does nothing.
        if context.isDemo { return [.welcome, .ready] }

        var steps: [Step] = [.welcome, .signIn]
        if !context.notificationsDenied { steps.append(.reminders) }
        if context.hasCareerChoice { steps.append(.career) }
        if !context.isWeBeepConnected { steps.append(.weBeep) }
        steps.append(.ready)
        return steps
    }

    /// The step before this one, or nil at the start.
    static func previous(before step: Step, in context: Context) -> Step? {
        let steps = steps(in: context)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// Whether a back button belongs on this step.
    ///
    /// Not simply "is there a step behind it". Once there is a session, the
    /// step behind is the sign-in, and offering to sign in again over a live
    /// session ends with the IdP replaying the existing grant and the student
    /// wondering what they just did. Everything else is re-readable, which is
    /// the point: the notifications step spends a permission iOS grants once,
    /// and someone who wants to re-read the page before spending it should be
    /// able to.
    static func canGoBack(from step: Step, in context: Context) -> Bool {
        guard let previous = previous(before: step, in: context) else { return false }
        if context.isSignedIn, previous == .signIn { return false }
        return true
    }

    /// The step to show after this one, or nil at the end.
    ///
    /// Tolerates a `step` that is no longer in the sequence — signing in can
    /// remove one, and the flow must move forward rather than stall on a step
    /// that stopped applying while it was on screen.
    static func next(after step: Step, in context: Context) -> Step? {
        let steps = steps(in: context)
        if let index = steps.firstIndex(of: step) {
            return steps.indices.contains(index + 1) ? steps[index + 1] : nil
        }
        // Not in the sequence any more: fall forward to the first step that
        // comes after it in the canonical order and still applies.
        guard let position = Step.allCases.firstIndex(of: step) else { return nil }
        return steps.first { Step.allCases.firstIndex(of: $0)! > position }
    }
}

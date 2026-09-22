import Foundation

/// Which steps the first run is made of, and in what order.
///
/// The sequence depends on the account behind it, and the account is not known
/// until halfway through, so it is derived from a ``Context`` on every query rather
/// than built once at the start — the sign-in step is precisely what changes the
/// context.
///
/// ``OnboardingState`` holds the cursor over this.
nonisolated enum OnboardingFlow {
    /// One screen of the first run. The declaration order is the canonical order
    /// ``next(after:in:)`` falls forward through.
    enum Step: String, CaseIterable, Identifiable, Sendable {
        /// What the app is, before asking for anything.
        case welcome
        /// The Politecnico's own sign-in.
        case signIn
        /// Notification permission, and how far ahead to be reminded.
        case reminders
        /// Which enrolment to use, when there is more than one.
        case career
        /// Course materials, which sign in separately.
        case weBeep
        /// What was set up, and where to change it later.
        case ready

        /// The raw value.
        var id: String { rawValue }
    }

    /// What the flow knows about the account at the moment it is asked.
    struct Context: Equatable, Sendable {
        /// Whether there is a live session.
        var isSignedIn = false
        /// Whether the student chose to explore the sample data instead of signing in.
        var isDemo = false
        /// Whether the account has more than one enrolment to choose between.
        var hasCareerChoice = false
        /// Whether course materials are already connected.
        var isWeBeepConnected = false
        /// Whether iOS has been asked once and refused. Asking again prompts for nothing,
        /// so the step is skipped.
        var notificationsDenied = false

        /// Creates a context.
        ///
        /// - Parameters:
        ///   - isSignedIn: Whether there is a live session.
        ///   - isDemo: Whether the student chose the sample data.
        ///   - hasCareerChoice: Whether there is more than one enrolment.
        ///   - isWeBeepConnected: Whether course materials are connected.
        ///   - notificationsDenied: Whether notification permission was already refused.
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
    ///
    /// Sample data yields ``Step/welcome`` and ``Step/ready`` alone: it needs no
    /// account, no career and no WeBeep, and nothing is scheduled from it. Otherwise
    /// ``Step/reminders`` is dropped once permission has been refused,
    /// ``Step/career`` appears only with more than one enrolment, and ``Step/weBeep``
    /// is dropped once materials are connected.
    ///
    /// - Parameter context: What the flow should take into account.
    /// - Returns: The applicable steps.
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

    /// The step before a given one.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the flow should take into account.
    /// - Returns: The preceding step, or `nil` at the start or when `step` no longer
    ///   applies.
    static func previous(before step: Step, in context: Context) -> Step? {
        let steps = steps(in: context)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// Whether a back button belongs on a step.
    ///
    /// `false` when the step behind is ``Step/signIn`` and a session already exists:
    /// signing in again over a live session has the identity provider replay the
    /// existing grant. Every other step is re-readable, which matters for
    /// ``Step/reminders``, since it spends a permission iOS grants once.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the flow should take into account.
    /// - Returns: `true` when the student may step back.
    static func canGoBack(from step: Step, in context: Context) -> Bool {
        guard let previous = previous(before: step, in: context) else { return false }
        if context.isSignedIn, previous == .signIn { return false }
        return true
    }

    /// The step to show after a given one.
    ///
    /// Tolerates a step that no longer applies — signing in can remove one while it is
    /// on screen — by falling forward to the first applicable step that comes later in
    /// the canonical order.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the flow should take into account.
    /// - Returns: The next step, or `nil` when the flow is finished.
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

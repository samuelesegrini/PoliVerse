import SwiftUI

/// The first run: what the app is, then the account, then the handful of
/// settings that are worth asking for once rather than leaving to be
/// discovered.
///
/// ## Why a flow and not a screen
///
/// The old first screen was a logo and a login button. Everything the app
/// could do, every permission it wanted and every switch that changed what it
/// showed lived behind a gear icon the student had no reason to open —
/// including `useMockData`, which defaulted **on** and meant a fresh install
/// quietly showed invented lectures. Someone could use PoliVerse for a week
/// and never learn it had reminders, or that the timetable they were reading
/// was not theirs.
///
/// So the steps here are not decoration. Each one either explains something
/// that changes what the app does, or collects a setting the app cannot
/// sensibly guess.
///
/// The sequence itself is ``OnboardingFlow``; this view renders whatever that
/// says applies, and ``OnboardingState`` remembers where it got to.
struct OnboardingView: View {
    @Environment(OnboardingState.self) private var onboarding
    @Environment(Session.self) private var session
    @Environment(CareersModel.self) private var careers
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(NotificationModel.self) private var notifications
    @Environment(WhatsNewState.self) private var whatsNew
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the flow knows right now. Rebuilt on every render rather than
    /// stored, because signing in changes most of it.
    private var context: OnboardingFlow.Context {
        OnboardingFlow.Context(
            isSignedIn: session.student != nil,
            isDemo: session.useMockData,
            hasCareerChoice: careers.hasChoice,
            isWeBeepConnected: weBeep.isAuthenticated,
            notificationsDenied: notifications.authorization == .denied)
    }

    private var steps: [OnboardingFlow.Step] { OnboardingFlow.steps(in: context) }

    var body: some View {
        VStack(spacing: 0) {
            if onboarding.step != .welcome {
                HStack(spacing: 8) {
                    if OnboardingFlow.canGoBack(from: onboarding.step, in: context) {
                        Button {
                            onboarding.goBack(in: context)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                                // The chevron is small on purpose; what has to
                                // be 44 points is the area a thumb can miss by.
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Torna al passo precedente")
                        .accessibilityIdentifier("onboarding-back")
                    }
                    OnboardingProgress(steps: steps, current: onboarding.step)
                        .padding(.trailing, 4)
                }
                // Fixed, so the steps that have no back button do not draw
                // their progress bar four points higher than the ones that do.
                .frame(height: 44)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }

            Group {
                switch onboarding.step {
                case .welcome: WelcomeStepView(advance: advance)
                case .signIn: SignInStepView(advance: advance)
                case .reminders: RemindersStepView(advance: advance)
                case .career: CareerStepView(advance: advance)
                case .weBeep: WeBeepStepView(advance: advance)
                case .ready: ReadyStepView(finish: finish)
                }
            }
            // Each step is its own screen rather than a page in a scroll
            // view, so the transition has to say which way the flow is going —
            // and going *back* has to look like going back, or the animation
            // contradicts the button that caused it.
            .transition(stepTransition)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .snappy, value: onboarding.step)
        // One tick per move, forwards or back: the step changing is the whole
        // of what the student just did.
        .sensoryFeedback(.selection, trigger: onboarding.step)
        // The careers are needed before the career step can know whether to
        // exist, and they are only readable once there is a token.
        .task(id: session.student?.matricola) {
            guard session.student != nil, !session.useMockData else { return }
            await careers.load()
        }
    }

    /// Sliding, in the direction the flow is actually moving — and a plain
    /// cross-fade when the student has asked the system for less movement,
    /// since the direction is carried by the progress bar as well.
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let entering: Edge = onboarding.isMovingBack ? .leading : .trailing
        let leaving: Edge = onboarding.isMovingBack ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: entering).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity))
    }

    private func advance() {
        onboarding.advance(in: context)
    }

    /// Ends the first run, and stamps the version it ended on.
    ///
    /// Without the stamp the app would follow the tour with "what's new in
    /// 2.0" for someone who has never run anything but 2.0.
    private func finish() {
        whatsNew.adoptFirstRun()
        onboarding.complete()
    }
}

/// How far through, as dots rather than a number.
///
/// A count would be a promise the flow cannot keep: signing in can add a
/// career step or remove a WeBeep one, and "passo 3 di 5" that becomes 3 of 4
/// reads as a bug.
private struct OnboardingProgress: View {
    let steps: [OnboardingFlow.Step]
    let current: OnboardingFlow.Step

    private var tint = OnboardingTint()

    init(steps: [OnboardingFlow.Step], current: OnboardingFlow.Step) {
        self.steps = steps
        self.current = current
    }

    /// Where in the list the current step is, or the start if it has just
    /// stopped applying and the flow is about to fall forward off it.
    private var reached: Int { steps.firstIndex(of: current) ?? 0 }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    // Passed steps stay filled. Lighting only the current one
                    // made the bar a position indicator without a scale: five
                    // identical dots and one lit tells nobody whether they are
                    // near the end, which is the single thing the bar is for.
                    .fill(index <= reached ? tint.color : Color.secondary.opacity(0.25))
                    .opacity(index < reached ? 0.45 : 1)
                    .frame(height: 4)
            }
        }
        .animation(.snappy, value: reached)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        String(localized: "Passo \(reached + 1) di \(steps.count)")
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView().previewEnvironment()
}

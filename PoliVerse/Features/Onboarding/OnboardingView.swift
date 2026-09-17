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
                HStack(spacing: 12) {
                    if OnboardingFlow.canGoBack(from: onboarding.step, in: context) {
                        Button {
                            onboarding.goBack(in: context)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Torna al passo precedente")
                    }
                    OnboardingProgress(steps: steps, current: onboarding.step)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
            }

            Group {
                switch onboarding.step {
                case .welcome: WelcomeStepView(advance: advance)
                case .signIn: SignInStepView(advance: advance)
                case .reminders: RemindersStepView(advance: advance)
                case .career: CareerStepView(advance: advance)
                case .weBeep: WeBeepStepView(advance: advance)
                case .ready: ReadyStepView(finish: onboarding.complete)
                }
            }
            // Each step is its own screen rather than a page in a scroll
            // view, so the transition has to say which way the flow is going.
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.snappy, value: onboarding.step)
        // The careers are needed before the career step can know whether to
        // exist, and they are only readable once there is a token.
        .task(id: session.student?.matricola) {
            guard session.student != nil, !session.useMockData else { return }
            await careers.load()
        }
    }

    private func advance() {
        onboarding.advance(in: context)
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps) { step in
                Capsule()
                    .fill(step == current ? Theme.brand : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        guard let index = steps.firstIndex(of: current) else { return "" }
        return String(localized: "Passo \(index + 1) di \(steps.count)")
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView().previewEnvironment()
}

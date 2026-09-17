import SwiftUI

/// Routes between login and the tab bar, and adapts to iPad width.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            // The first run explains the app before asking for an account, so
            // it owns the sign-in rather than sitting in front of it. Once it
            // has been through, a signed-out session is someone who already
            // knows what this is — switching career, or coming back — and
            // gets the plain login screen instead.
            case .signedOut, .failed, .exchangingCode:
                if onboarding.isComplete { LoginView() } else { OnboardingView() }
            case .signedIn:
                if !onboarding.isComplete {
                    OnboardingView()
                } else {
                    NewRootView()
                }
            }
        }
        // Sample data is its own population in the field numbers.
        .onChange(of: session.useMockData, initial: true) { _, sample in
            PerformanceStates.dataSource(usesSampleData: sample)
        }
        .task {
            // Launch, as a student feels it, ends when the account is back —
            // not at the first frame, which is a spinner.
            await PerformanceMonitor.trackLaunch("session-restore") {
                let interval = PerfSignpost.begin(.sessionRestore)
                defer { PerfSignpost.end(interval) }
                await session.login.restore()
            }
            // After the restore, not before: a token in the Keychain is what
            // says this install predates the onboarding.
            if session.student != nil { onboarding.adoptExistingInstall() }
        }
    }
}

import SwiftUI

/// The screen for someone who is signed out but has already been through
/// onboarding — switching career, or coming back after signing out.
///
/// The first run is ``OnboardingView`` instead: it says what the app is before
/// asking for an account. This one does not, because by the time anyone sees
/// it they have used the app — but it still reuses ``OnboardingStepLayout``,
/// the same shape as onboarding's own sign-in step (``SignInStepView``), which
/// shows this identical ``PoliMiSignInButton``. Two screens presenting the
/// same choice looked like two different apps when this one had its own
/// centred, spacer-driven layout instead.
struct LoginView: View {
    /// The view's content.
    var body: some View {
        OnboardingStepLayout(
            symbol: "graduationcap.fill",
            title: "Bentornato su PoliVerse",
            detail: "Corsi, materiali e carriera in un posto solo."
        ) {
            OnboardingPoint(
                symbol: "lock.shield",
                text: "PoliVerse non è un'app ufficiale del Politecnico di Milano: le credenziali si inseriscono solo sulla pagina del Politecnico o del tuo gestore.")
        } actions: {
            PoliMiSignInButton()
        }
    }
}

// MARK: - Previews

#Preview("Accesso") {
    LoginView().previewEnvironment()
}

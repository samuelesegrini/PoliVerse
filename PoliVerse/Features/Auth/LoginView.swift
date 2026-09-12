import SwiftUI

/// The screen for someone who is signed out but has already been through
/// onboarding — switching career, or coming back after signing out.
///
/// The first run is ``OnboardingView`` instead: it says what the app is before
/// asking for an account. This one does not, because by the time anyone sees
/// it they have used the app.
struct LoginView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brand.gradient)

            VStack(spacing: 8) {
                Text("PoliVerse")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                Text("Corsi, materiali e carriera in un posto solo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            PoliMiSignInButton()

            Text("PoliVerse non è un'app ufficiale del Politecnico di Milano. Le credenziali vengono inserite solo nella pagina di ateneo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

// MARK: - Previews

#Preview("Accesso") {
    LoginView().previewEnvironment()
}

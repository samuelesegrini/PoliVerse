import SwiftUI

/// The account step: what signing in reaches, and what it does not.
///
/// Said before the IdP opens rather than after, because "accedi con account
/// Polimi" on its own does not tell anyone whether this app can read their
/// password (it cannot), what it will pull (their own data), or where it goes
/// (nowhere — the device).
struct SignInStepView: View {
    @Environment(Session.self) private var session
    @Environment(CareersService.self) private var careers
    let advance: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.badge.key.fill",
            title: "Accedi con l'account del Politecnico",
            detail: "L'accesso avviene sulla pagina dei Servizi Online, nella stessa finestra che useresti dal browser. PoliVerse non vede la password: riceve solo un codice temporaneo e lo conserva nel portachiavi del dispositivo."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPoint(
                    symbol: "lock.shield",
                    text: "Credenziali e SPID/CIE restano sulla pagina di ateneo.")
                OnboardingPoint(
                    symbol: "iphone",
                    text: "I dati scaricati restano sul telefono: non c'è un server di PoliVerse.")
                OnboardingPoint(
                    symbol: "eye.slash",
                    text: "Nessuna statistica, nessun tracciamento, nessun account da creare.")
            }
        } actions: {
            PoliMiSignInButton()
        }
        // The token arriving is the *only* thing that moves this step on —
        // the id changes at exactly that moment, and it covers the second
        // pass through onboarding, where the session is already live. An
        // `onSignedIn` callback on the button as well would advance twice and
        // skip the reminders step, whose permission prompt iOS only ever
        // shows once.
        .task(id: session.student?.matricola) {
            guard session.student != nil else { return }
            // Before advancing, not after: whether there is a career step at
            // all depends on how many enrolments this account has, and the
            // flow is about to ask.
            await careers.load()
            advance()
        }
    }
}

// MARK: - Previews

#Preview("Accesso") {
    SignInStepView(advance: {}).previewEnvironment()
}

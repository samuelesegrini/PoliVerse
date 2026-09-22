import SwiftUI

/// Covers the web view while it is doing something the student cannot act on.
///
/// There are three such moments, and together they are most of the login: the
/// Servizi Online app bootstrapping, the chooser page being pressed for them,
/// and the code being exchanged on the way back. A visible redirect chain is
/// the part of a login that looks most like a failure.
struct LoginWaitingView: View {
    /// How the student chose to sign in, which decides what the screen says.
    let method: PoliMiLoginMethod
    /// Uncovers the web view. Offered after a few seconds so that no spinner
    /// here can ever be a dead end, whatever we failed to anticipate: the
    /// student can always get to the Politecnico's own page and finish by
    /// hand.
    var reveal: () -> Void = {}

    /// Whether the way out is offered, after the wait has run long enough that something may
    /// have gone wrong.
    @State private var showsEscape = false

    /// The view's content.
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if showsEscape {
                Button("Mostra la pagina del Politecnico", action: reveal)
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.brand)
                    .transition(.opacity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .animation(.snappy, value: showsEscape)
        // Eight seconds: longer than any step of this login takes on a working
        // connection, so the button is an admission of a problem rather than an
        // invitation to interrupt a flow that is going fine.
        .task {
            try? await Task.sleep(for: .seconds(8))
            showsEscape = true
        }
    }

    /// What is happening, in the words of the method the student chose.
    private var message: LocalizedStringKey {
        switch method {
        case .password: "Apro la pagina del Politecnico…"
        case .spid(let provider): "Ti porto su \(provider.name)…"
        case .cie: "Apro l'accesso con Carta d'Identità Elettronica…"
        case .eidas: "Apro l'accesso eIDAS…"
        case .eduGAIN: "Apro l'accesso EduGAIN…"
        }
    }
}

// MARK: - Previews

#Preview("Attesa") {
    LoginWaitingView(method: .password)
}

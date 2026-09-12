import SwiftUI

/// Covers the web view while it is doing something the student cannot act on.
///
/// There are three such moments, and together they are most of the login: the
/// Servizi Online app bootstrapping, the chooser page being pressed for them,
/// and the code being exchanged on the way back. Each used to be visible, and
/// a redirect chain is the part of a login that looks most like a failure.
struct LoginWaitingView: View {
    let method: PoliMiLoginMethod

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

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

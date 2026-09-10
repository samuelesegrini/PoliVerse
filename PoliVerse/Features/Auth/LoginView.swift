import SwiftUI

/// Presents the Politecnico IdP and hands the authcode to ``Session``.
struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var showingWeb = false
    @State private var webError: String?

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

            if case .exchangingCode = session.state {
                ProgressView("Accesso in corso…")
            } else {
                Button {
                    webError = nil
                    showingWeb = true
                } label: {
                    Text("Accedi con account Polimi")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(Theme.brand, in: .capsule)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }

            if let message = webError ?? failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("PoliVerse non è un'app ufficiale del Politecnico di Milano. Le credenziali vengono inserite solo nella pagina di ateneo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .sheet(isPresented: $showingWeb) {
            NavigationStack {
                LoginWebView(
                    url: PoliMiOAuth.authorizationURL,
                    onCode: { code in
                        showingWeb = false
                        Task { await session.completeLogin(authCode: code) }
                    },
                    onError: { error in
                        showingWeb = false
                        webError = error.localizedDescription
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Accesso Polimi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showingWeb = false }
                    }
                }
            }
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = session.state { return message }
        return nil
    }
}

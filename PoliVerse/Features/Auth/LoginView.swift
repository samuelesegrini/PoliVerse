import SwiftUI

/// Presents the Politecnico IdP and hands the authcode to ``Session``.
struct LoginView: View {
    @Environment(Session.self) private var session
    @Environment(CieIDRouter.self) private var cieID
    @State private var showingWeb = false
    @State private var webError: String?
    @State private var showingCieIDMissing = false
    @State private var logoutURL: URL?
    @State private var isPreparing = false

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
                    isPreparing = true
                    Task {
                        // Clears any stored token and ends the SSO session, so
                        // the IdP has to mint a new grant rather than replay
                        // the old one.
                        logoutURL = await session.prepareForLogin()
                        isPreparing = false
                        showingWeb = true
                    }
                } label: {
                    Group {
                        if isPreparing {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Accedi con account Polimi").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .disabled(isPreparing)
                .background(Theme.brand, in: .capsule)
                .foregroundStyle(Theme.onAccent)
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
                PoliMiAppLoginWebView(
                    oauthParams: session.directory.oauth,
                    router: cieID,
                    onCredentials: { token in
                        showingWeb = false
                        Task {
                            await session.completeLogin(token: token)
                            // Consumed either way: a hint that did not take is
                            // not worth re-applying to every future login.
                            session.pendingMatricola = nil
                        }
                    },
                    onError: { error in
                        showingWeb = false
                        webError = error.localizedDescription
                    },
                    onCieIDMissing: { showingCieIDMissing = true },
                    // Carries the enrolment the user asked to switch to, if
                    // they got here from the career switcher.
                    flow: .login(hintMatricola: session.pendingMatricola)
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Servizi Online")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showingWeb = false }
                    }
                }
                .overlay(alignment: .bottom) {
                    if cieID.isAwaitingCieID {
                        CieIDWaitingBanner()
                    }
                }
                .alert("App CieID non installata", isPresented: $showingCieIDMissing) {
                    Button("Apri App Store") { cieID.openAppStore() }
                    Button("Annulla", role: .cancel) {}
                } message: {
                    Text("Per accedere con la Carta d'Identità Elettronica serve l'app CieID.")
                }
            }
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = session.state { return message }
        return nil
    }
}

// MARK: - Previews

#Preview("Accesso") {
    LoginView().previewEnvironment()
}

import SwiftUI

/// The Politecnico's sign-in, run on the recordings' own web session.
///
/// Starts at ``RecordingsWebKit/entry`` and ends as soon as the flow reaches recman:
/// by then the SSO cookie is in ``RecordingsWebKit/dataStore``, which is all the
/// hidden browser needs to walk the archive by itself. Nothing is copied into the
/// app's shared cookie jar.
struct RecordingsSignInSheet: View {
    /// The shared ``CieIDRouter``, from the environment.
    @Environment(CieIDRouter.self) private var cieID
    /// Closes this sheet.
    @Environment(\.dismiss) private var dismiss

    /// Run once the sign-in reaches recman, so the caller can read the archive.
    let onSuccess: () async -> Void

    /// Why the sign-in failed, or `nil` when it has not.
    @State private var errorMessage: String?
    /// Whether the prompt to install CieID is up.
    @State private var showingCieIDMissing = false

    /// The view's content.
    var body: some View {
        NavigationStack {
            AuthWebView(
                startURL: RecordingsWebKit.entry,
                router: cieID,
                decide: { url in
                    guard RecmanParser.isRecman(url) else { return .allow }
                    return .finish {
                        dismiss()
                        Task { await onSuccess() }
                    }
                },
                onError: { errorMessage = userFacingMessage($0) },
                onCieIDMissing: { showingCieIDMissing = true },
                dataStore: RecordingsWebKit.dataStore,
                adoptsCookies: false
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if cieID.isAwaitingCieID {
                    CieIDWaitingBanner()
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Archivio registrazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
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

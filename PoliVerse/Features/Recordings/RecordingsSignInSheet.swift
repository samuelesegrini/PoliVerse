import SwiftUI

/// The Politecnico's sign-in, run on the recordings' own web session.
///
/// Starts at ``RecordingsWebKit/entry`` and ends as soon as the flow reaches recman:
/// by then the SSO cookie is in ``RecordingsWebKit/dataStore``, which is all the
/// hidden browser needs to walk the archive by itself. Nothing is copied into the
/// app's shared cookie jar.
struct RecordingsSignInSheet: View {
    /// Where the sign-in starts. The archive's entry by default.
    var start: URL = RecordingsWebKit.entry
    /// Whether a page is where the sign-in has arrived. Recman, by default.
    var arrived: (URL) -> Bool = RecmanParser.isRecman
    /// The sheet's title.
    var title: LocalizedStringKey = "Archivio registrazioni"
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
                startURL: start,
                router: cieID,
                decide: { url in
                    guard arrived(url) else { return .allow }
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
            .navigationTitle(title)
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

/// Webex's sign-in, on the recordings' session.
///
/// Webex asks for the email once, then hands over to the Politecnico's single
/// sign-on, which the session already holds. It ends when the recording's playback
/// page opens; Webex's cookies then stay in the session and are kept with it, so the
/// next recording plays without asking.
struct WebexSignInSheet: View {
    /// The recording's Webex address.
    let address: URL
    /// Run once the playback page opens, so the caller can try again.
    let onSuccess: () -> Void

    /// The view's content.
    var body: some View {
        RecordingsSignInSheet(
            start: address,
            arrived: { url in
                url.host?.hasSuffix("webex.com") == true && url.path.contains("/recording/playback/")
            },
            title: "Accesso a Webex",
            onSuccess: {
                await RecordingsWebKit.saveSession()
                onSuccess()
            })
    }
}

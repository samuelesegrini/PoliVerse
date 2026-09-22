import SwiftUI

/// Shown between the login web sheet closing and the account being confirmed.
///
/// `LoginWaitingView` covers the same wait while the web sheet is still on
/// screen; this is the part after it: CieID/SPID/eIDAS hand control back by
/// backgrounding and re-foregrounding the app, which dismisses the sheet
/// before `LoginFlow.completeLogin` has finished exchanging the code and
/// confirming the account. Without this, `RootView` fell back to the plain
/// signed-out screen for that stretch, which read as the login having quietly
/// failed rather than still being in progress.
struct SigningInView: View {
    /// The view's content.
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Accesso in corso…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Previews

#Preview("Accesso in corso") {
    SigningInView()
}

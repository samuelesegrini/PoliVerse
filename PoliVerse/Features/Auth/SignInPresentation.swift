import SwiftUI

/// Shared presentation policy; browser adapters retain their own credentials,
/// cookies, completion rules, and error-dismiss behavior.
struct SignInPresentation<Content: View>: View {
    let title: LocalizedStringKey
    let errorMessage: String?
    @Binding var showingCieIDMissing: Bool
    let cancel: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(CieIDRouter.self) private var cieID

    var body: some View {
        NavigationStack {
            content()
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
                        Button("Annulla", action: cancel)
                    }
                }
                .alert("App CieID non installata", isPresented: $showingCieIDMissing) {
                    Button("Apri App Store") { cieID.openAppStore() }
                    Button("Annulla", role: .cancel) {}
                } message: {
                    Text("Per accedere con la Carta d'Identità Elettronica serve l'app CieID.")
                }
        }
        .macSheetSize(width: 1040, height: 860, resizable: true)
    }
}

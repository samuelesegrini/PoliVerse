import SwiftUI

/// Says, permanently, that none of this is real.
///
/// `useMockData` used to be a Settings toggle that defaulted on, which meant
/// the app's most misleading state was also its quietest one: invented
/// lectures, invented grades, and nothing on screen to say so. The first run
/// now asks outright, but a choice made once on a welcome screen is not a
/// thing anyone remembers a week later — so while sample data is on, it says
/// so above every tab, with the way out attached.
struct DemoModeBanner: View {
    @Environment(Session.self) private var session

    var body: some View {
        if session.useMockData {
            HStack(spacing: 8) {
                Image(systemName: "theatermasks.fill")
                Text("Dati di esempio")
                    .fontWeight(.medium)
                Spacer()
                Button("Esci") { session.useMockData = false }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.brand)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.yellow.opacity(0.15))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Stai guardando dati di esempio, non il tuo account.")
        }
    }
}

// MARK: - Previews

#Preview("Dati di esempio") {
    DemoModeBanner().previewEnvironment()
}

import SwiftUI

/// Preview features use ordinary native switches and preserve a working fallback.
struct BetaFeaturesView: View {
    @Environment(FeatureFlags.self) private var flags

    var body: some View {
        List {
            ForEach(flags.availableFeatures) { feature in
                Section {
                    Toggle(isOn: Binding(get: { flags.isEnabled(feature) },
                                         set: { flags.setEnabled($0, for: feature) })) {
                        Text(feature.title)
                    }
                    .accessibilityIdentifier("beta-" + feature.rawValue)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(feature.detail)
                        ForEach(Array(feature.highlights.enumerated()), id: \.offset) { _, line in
                            Label { Text(line) } icon: { Image(systemName: "checkmark") }
                        }
                    }
                }
                .lookRow()
            }
            Section {
                if flags.availableFeatures.isEmpty {
                    Text("Nessuna funzione in anteprima disponibile in questa build.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Disattiva tutte le anteprime") { flags.reset() }
                        .accessibilityIdentifier("beta-reset")
                }
            } footer: {
                Text("Le anteprime sono facoltative e possono cambiare. Le scelte restano su questo dispositivo e funzionano anche senza connessione.")
            }
            .lookRow()
            Section {
                Link(destination: URL(string: "https://github.com/samuelesegrini/PoliVerse/issues/new")!) {
                    Label("Segnala un problema", systemImage: "bubble.left.and.bubble.right")
                }
            } footer: {
                Text("Non includere credenziali, matricola o dati della carriera nella segnalazione pubblica.")
            }
            .lookRow()
        }
        .lookList()
        .navigationTitle("Anteprime")
        .accessibilityIdentifier("beta-features")
    }
}

struct ReleaseHistoryView: View {
    var body: some View {
        List {
            ForEach(ReleaseNotes.all.filter { !ReleaseNotes.isOlder(Bundle.main.releaseVersion, than: $0.version) }) { note in
                Section {
                    ForEach(note.items) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: item.symbol).foregroundStyle(.tint) }
                    }
                } header: { Text("Versione \(note.version)") }
                  footer: { Text(note.headline) }
                  .lookRow()
            }
        }
        .lookList()
        .navigationTitle("Tutte le novità")
        .accessibilityIdentifier("release-history")
    }
}

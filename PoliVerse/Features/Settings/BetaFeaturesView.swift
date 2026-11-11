import SwiftUI

/// Preview features use ordinary native switches and preserve a working fallback.
struct BetaFeaturesView: View {
    @Environment(FeatureFlags.self) private var flags

    var body: some View {
        List {
            Section {
                ForEach(flags.availableFeatures) { feature in
                    Toggle(isOn: Binding(get: { flags.isEnabled(feature) },
                                         set: { flags.setEnabled($0, for: feature) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                            Text(feature.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("beta-" + feature.rawValue)
                }
                if flags.availableFeatures.isEmpty {
                    Text("Nessuna funzione in anteprima disponibile in questa build.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Le anteprime sono facoltative e possono cambiare. Le scelte restano su questo dispositivo e funzionano anche senza connessione.")
            }
            .lookRow()

            if !flags.availableFeatures.isEmpty {
                Section {
                    Button("Disattiva tutte le anteprime") { flags.reset() }
                        .accessibilityIdentifier("beta-reset")
                }
                .lookRow()
            }
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
        .navigationTitle("Funzioni in anteprima")
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

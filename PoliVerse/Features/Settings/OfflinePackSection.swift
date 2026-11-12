import SwiftUI

/// The offline pack in Impostazioni: whether it runs, what it holds and how old,
/// the space it takes, and a way to start it now.
struct OfflinePackSection: View {
    @Environment(OfflinePack.self) private var pack
    /// The space the stored copies take, measured when the section appears and
    /// after each run.
    @State private var bytes: Int?

    var body: some View {
        @Bindable var pack = pack
        Section {
            Toggle("Scarica per l’uso offline", isOn: $pack.isEnabled)
            ForEach(OfflineItem.allCases, id: \.self) { item in
                LabeledContent {
                    status(of: item)
                } label: {
                    Text(item.title)
                }
                .accessibilityIdentifier("offline-\(item.rawValue)")
            }
            if let bytes {
                LabeledContent("Spazio usato dai dati salvati",
                               value: bytes.formatted(.byteCount(style: .file)))
            }
            Button {
                Task {
                    await pack.run(byHand: true)
                    bytes = await Self.measure()
                }
            } label: {
                Label(pack.isRunning ? "Download in corso…" : "Scarica ora", systemImage: "arrow.down.circle")
            }
            .disabled(pack.isRunning)
            .accessibilityIdentifier("offline-run")
        } header: {
            Text("Offline")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.isEnabled
                     ? "Una volta al giorno, con il Wi‑Fi e quando il telefono è inattivo, l’app scarica orario, aule di domani, piante e materiali dei corsi, così si aprono anche senza rete. Conta nel limite giornaliero delle richieste in anticipo."
                     : "L’app tiene solo ciò che apri. Puoi comunque scaricare tutto ora.")
                if let stopped = pack.stopped { Text(stopped) }
            }
        }
        .animation(.snappy(duration: 0.25), value: pack.isRunning)
        .task { bytes = await Self.measure() }
    }

    /// What one item says: in progress, stored and how long ago, or not yet.
    @ViewBuilder
    private func status(of item: OfflineItem) -> some View {
        if pack.current == item {
            ProgressView().controlSize(.small)
        } else if let date = pack.storedAt(item) {
            Text("pronto, \(date.formatted(.relative(presentation: .named)))")
                .foregroundStyle(.secondary)
        } else {
            Text("non ancora scaricato").foregroundStyle(.secondary)
        }
    }

    /// The size of the app's stored copies, read off the main thread.
    private static func measure() async -> Int {
        await Task.detached(priority: .utility) {
            OfflineStore.shared.sizeInBytes + DiskCache.sizeInBytes()
        }.value
    }
}

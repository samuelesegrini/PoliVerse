import SwiftUI

/// Whether the app prepares what the next lecture needs, and on which networks.
///
/// Shows today's count of requests sent ahead against the daily limit, so the
/// cost of the switch is in plain sight.
struct PrefetchSettingsSection: View {
    @AppStorage(SpeculativeBudget.Settings.enabledKey) private var enabled = true
    @AppStorage(SpeculativeBudget.Settings.meteredKey) private var onCellular = false
    /// Today's count, read from the gate when the section appears.
    @State private var sentToday: Int?

    private var limit: Int { SpeculativeBudget.Settings().dailyLimit }

    var body: some View {
        Section {
            Toggle("Prepara in anticipo", isOn: $enabled)
            if enabled {
                Toggle("Anche con la rete cellulare", isOn: $onCellular)
            }
            if let sentToday {
                LabeledContent("Richieste in anticipo oggi", value: "\(sentToday) di \(limit)")
                    .monospacedDigit()
            }
        } header: {
            Text("Preparazione in anticipo")
        } footer: {
            Text(enabled
                 ? "Un’ora prima di una lezione l’app scarica gli orari dell’aula, la pianta e la pagina del corso, così si aprono subito. Mai con la modalità Dati ridotti, il Risparmio energetico o il telefono caldo."
                 : "L’app scarica solo ciò che apri.")
        }
        .animation(.snappy(duration: 0.25), value: enabled)
        .task { sentToday = await RequestGate.shared.sentToday() }
    }
}

import SwiftUI
import UserNotifications

/// Which reminders to send, and how far ahead.
struct NotificationSettingsView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var notifications = notifications

        Form {
            switch notifications.authorization {
            case .notDetermined:
                Section {
                    Button {
                        Task {
                            await notifications.requestAuthorization()
                            await reschedule()
                        }
                    } label: {
                        Label("Attiva i promemoria", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Tutto resta sul dispositivo: i promemoria vengono calcolati dal tuo orario e programmati localmente, senza inviare nulla.")
                }

            case .denied:
                Section {
                    // Asking again does nothing: the system remembers a
                    // refusal, so the only route left is Settings.
                    Label("Promemoria non consentiti", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Button("Apri Impostazioni") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }

            default:
                Section("Cosa notificare") {
                    Toggle("Lezioni", isOn: $notifications.preferences.lectures)
                    Toggle("Scadenze", isOn: $notifications.preferences.deadlines)
                    Toggle("Esami", isOn: $notifications.preferences.exams)
                    Toggle("Chiusura iscrizioni", isOn: $notifications.preferences.enrolments)
                }

                Section {
                    Toggle("Novità sugli esami", isOn: $notifications.preferences.examUpdates)
                } footer: {
                    Text("Esiti, aule, appelli spostati e finestre di rifiuto, appena l'app se ne accorge. Il resto arriva in un riepilogo alle 18:00, e di notte solo ciò che è urgente.")
                }

                Section {
                    Toggle("Cerca la mia matricola negli esiti", isOn: $notifications.preferences.readResultsFiles)
                        .disabled(!notifications.preferences.examUpdates)
                } footer: {
                    // Said plainly: the file lists other students.
                    Text("Quando un docente pubblica un file di esiti su WeBeep, l'app lo apre sul telefono e cerca solo la tua matricola. Conserva soltanto se compari e il tuo voto, che resta nell'app e non appare nelle notifiche; il file e i dati degli altri non vengono salvati né inviati. Funziona con PDF testuali e CSV.")
                }

                Section {
                    Picker("Anticipo lezioni", selection: $notifications.preferences.leadMinutes) {
                        Text("5 minuti").tag(5)
                        Text("10 minuti").tag(10)
                        Text("15 minuti").tag(15)
                        Text("30 minuti").tag(30)
                        Text("1 ora").tag(60)
                    }
                } footer: {
                    Text("Scadenze, esami e chiusura iscrizioni arrivano alle 18:00 del giorno prima, quando c'è ancora tempo per agire.")
                }

                Section {
                    if notifications.scheduled.isEmpty {
                        Text("Nessun promemoria programmato.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(notifications.scheduled.prefix(10)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline)
                                Text(item.fireDate.formatted(
                                    .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                        .hour().minute().locale(locale)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Programmati · \(notifications.scheduled.count)")
                } footer: {
                    // Worth saying: the cap is Apple's, not a choice, and it
                    // explains why a reminder three weeks out never arrives.
                    Text("iOS consente al massimo \(NotificationPlan.limit) promemoria in attesa: vengono tenuti i più vicini.")
                }
            }
        }
        .navigationTitle("Promemoria")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notifications.refreshAuthorization()
            await reschedule()
        }
        // Any change to what or how far ahead reschedules the lot.
        .onChange(of: notifications.preferences) { _, _ in
            Task { await reschedule() }
        }
    }

    private func reschedule() async {
        await notifications.reschedule(
            events: agenda.events, exams: career.sessions, updates: feed.updates)
    }
}

// MARK: - Previews

#Preview("Promemoria") {
    NotificationSettingsView().previewInNavigation()
}

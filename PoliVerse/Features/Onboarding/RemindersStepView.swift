import SwiftUI
import UserNotifications

/// Reminders: the permission, and the one preference worth setting now.
///
/// Asked here rather than at first launch because iOS gives one prompt per
/// install and a refusal is permanent — so it is worth spending a screen
/// explaining what the notifications are before spending the prompt.
struct RemindersStepView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(UpdateFeed.self) private var feed
    let advance: () -> Void

    @State private var isAsking = false

    var body: some View {
        @Bindable var notifications = notifications

        OnboardingStepLayout(
            symbol: "bell.badge.fill",
            title: "Promemoria per lezioni ed esami",
            detail: "Calcolati sul tuo orario e programmati sul dispositivo. Niente esce dal telefono: non c'è un server che sa quando hai lezione."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if notifications.authorization == .notDetermined {
                    OnboardingPoint(
                        symbol: "clock",
                        text: "Una notifica prima di ogni lezione, con l'aula.")
                    OnboardingPoint(
                        symbol: "calendar.badge.exclamationmark",
                        text: "Scadenze, appelli e chiusura iscrizioni alle 18:00 del giorno prima.")
                } else {
                    // Granted: the permission is spent, so this becomes the
                    // preferences it exists to serve.
                    Toggle("Lezioni", isOn: $notifications.preferences.lectures)
                    Toggle("Scadenze", isOn: $notifications.preferences.deadlines)
                    Toggle("Esami", isOn: $notifications.preferences.exams)
                    Picker("Anticipo lezioni", selection: $notifications.preferences.leadMinutes) {
                        Text("5 minuti").tag(5)
                        Text("10 minuti").tag(10)
                        Text("15 minuti").tag(15)
                        Text("30 minuti").tag(30)
                        Text("1 ora").tag(60)
                    }
                    Text("Si cambia quando vuoi da Impostazioni · Promemoria.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            if notifications.authorization == .notDetermined {
                OnboardingPrimaryButton(title: "Attiva i promemoria") {
                    isAsking = true
                    Task {
                        await notifications.requestAuthorization()
                        await notifications.reschedule(
                            events: agenda.events, exams: career.sessions,
                            updates: feed.updates)
                        isAsking = false
                        // Stays on this step when granted: the preferences
                        // above have just appeared and are worth a look.
                        if notifications.authorization == .denied { advance() }
                    }
                }
                .disabled(isAsking)
                OnboardingSkipButton(title: "Non ora", action: advance)
            } else {
                OnboardingPrimaryButton(title: "Continua", action: advance)
            }
        }
    }
}

// MARK: - Previews

#Preview("Promemoria") {
    RemindersStepView(advance: {}).previewEnvironment()
}

import SwiftUI
import UserNotifications

/// Reminders: the permission, and the one preference worth setting now.
///
/// Asked here rather than at first launch because iOS gives one prompt per
/// install and a refusal is permanent — so it is worth spending a screen
/// explaining what the notifications are before spending the prompt.
struct RemindersStepView: View {
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    let advance: () -> Void

    /// The onboarding flow's accent, taken from the look in use.
    private var tint = OnboardingTint()
    /// True while the system prompt is on screen, so the button cannot be pressed twice.
    @State private var isAsking = false

    /// The view's content.
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
                    // preferences it exists to serve. In a card, because bare
                    // controls stacked on the page background are the one
                    // place in the app where a switch has no row under it.
                    VStack(spacing: 10) {
                        Toggle("Lezioni", isOn: $notifications.preferences.lectures)
                        Divider()
                        Toggle("Scadenze", isOn: $notifications.preferences.deadlines)
                        Divider()
                        Toggle("Esami", isOn: $notifications.preferences.exams)
                        Divider()
                        Picker("Anticipo lezioni", selection: $notifications.preferences.leadMinutes) {
                            Text("5 minuti").tag(5)
                            Text("10 minuti").tag(10)
                            Text("15 minuti").tag(15)
                            Text("30 minuti").tag(30)
                            Text("1 ora").tag(60)
                        }
                    }
                    .font(.subheadline)
                    .tint(tint.color)
                    .padding(14)
                    .lookCard(cornerRadius: 16)

                    Text("Si cambia quando vuoi da Impostazioni · Promemoria.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } actions: {
            if notifications.authorization == .notDetermined {
                OnboardingPrimaryButton(title: "Attiva i promemoria", isBusy: isAsking) {
                    isAsking = true
                    Task {
                        await notifications.requestAuthorization()
                        await notifications.reschedule(
                            events: agenda.events, exams: career.sessions,
                            assignments: feed.deadlines, updates: feed.updates)
                        isAsking = false
                        // Stays on this step when granted: the preferences
                        // above have just appeared and are worth a look.
                        if notifications.authorization == .denied { advance() }
                    }
                }
                OnboardingSkipButton(title: "Non ora", action: advance)
            } else {
                OnboardingPrimaryButton(title: "Continua", action: advance)
            }
        }
        // iOS's own prompt gives no feedback of its own once it closes, and on
        // a refusal the screen simply moves on — so the outcome is said in the
        // one channel that is not competing with the animation.
        .sensoryFeedback(trigger: notifications.authorization) { previous, current in
            guard previous == .notDetermined else { return nil }
            return current == .authorized ? .success : .error
        }
    }
}

// MARK: - Previews

#Preview("Promemoria") {
    RemindersStepView(advance: {}).previewEnvironment()
}

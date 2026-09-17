import SwiftUI

/// What was set up, and where each of it lives from now on.
///
/// The last screen of a setup is the only moment someone is certain to read a
/// map of where the settings went. Everything listed here is a real
/// destination in the app, not a summary of the flow.
///
/// Two screens rather than one branching four times: the student who signed in
/// is being told where their settings went, and the one exploring the sample
/// data is being told that none of it is real. Those have nothing in common
/// but the button at the bottom.
struct ReadyStepView: View {
    @Environment(Session.self) private var session
    let finish: () -> Void

    var body: some View {
        if session.useMockData {
            SampleDataReadyView(finish: finish)
        } else {
            AccountReadyView(finish: finish)
        }
    }
}

/// The end of the flow for someone who signed in.
private struct AccountReadyView: View {
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(NotificationModel.self) private var notifications
    let finish: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "checkmark.seal.fill",
            title: "Tutto pronto",
            detail: "Le impostazioni raccolte qui si cambiano tutte da Impostazioni, l'icona in alto a destra nella Home."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if notifications.authorization == .authorized {
                    OnboardingPoint(
                        symbol: "bell",
                        text: "Promemoria attivi · da Impostazioni · Promemoria cambi anticipo e tipi.")
                } else {
                    OnboardingPoint(
                        symbol: "bell.slash",
                        text: "Promemoria non attivi · si accendono da Impostazioni · Promemoria.")
                }
                if weBeep.isAuthenticated {
                    OnboardingPoint(
                        symbol: "books.vertical",
                        text: "WeBeep collegato · i materiali sono nella scheda WeBeep.")
                } else {
                    OnboardingPoint(
                        symbol: "books.vertical",
                        text: "WeBeep non collegato · si collega dalla scheda WeBeep.")
                }
                OnboardingPoint(
                    symbol: "person.text.rectangle",
                    text: "Matricola e carriere · Impostazioni · Matricola.")
                OnboardingPoint(
                    symbol: "square.grid.2x2",
                    text: "Widget e Centro di Controllo: tieni premuto sulla schermata Home per aggiungerli.")
                OnboardingPoint(
                    symbol: "arrow.clockwise",
                    text: "I dati si aggiornano da soli quando riapri l'app; trascina in giù per forzarlo.")
            }
        } actions: {
            OnboardingPrimaryButton(title: "Inizia", action: finish)
        }
    }
}

/// The end of the flow for someone who chose to look around first.
private struct SampleDataReadyView: View {
    let finish: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "theatermasks.fill",
            title: "Stai guardando dati di esempio",
            detail: "Nessun collegamento ai server del Politecnico: orari, voti e materiali qui dentro sono inventati, così puoi vedere com'è fatta l'app senza account."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPoint(
                    symbol: "theatermasks",
                    text: "Una striscia in cima a ogni schermata te lo ricorda.")
                OnboardingPoint(
                    symbol: "person.crop.circle.badge.checkmark",
                    text: "Per passare al tuo account: Impostazioni · Usa dati di esempio.")
                OnboardingPoint(
                    symbol: "door.left.hand.open",
                    text: "Le aule libere restano reali: sono dati pubblici e non servono credenziali.")
            }
        } actions: {
            OnboardingPrimaryButton(title: "Esplora l'app", action: finish)
        }
    }
}

// MARK: - Previews

#Preview("Pronto") {
    ReadyStepView(finish: {}).previewEnvironment()
}

import SwiftUI

/// What PoliVerse is, before it asks for anything.
///
/// Four pages, each one thing the app actually does, because a list of
/// features nobody reads is worse than none. The pages end on the choice
/// between a real account and the sample data — stated here rather than left
/// as a switch in Settings, which is where it used to live while being on by
/// default.
struct WelcomeStepView: View {
    @Environment(Session.self) private var session
    let advance: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "calendar.day.timeline.left",
             title: "L'orario, senza cercarlo",
             detail: "Le lezioni del giorno appena apri l'app, con l'aula e quanto manca. Sulla schermata di blocco e in Centro di Controllo, se vuoi."),
        Page(symbol: "books.vertical.fill",
             title: "I materiali di WeBeep",
             detail: "Dispense e registrazioni dei tuoi corsi, scaricabili per leggerle offline — in metropolitana, dove la rete del Politecnico non arriva."),
        Page(symbol: "chart.bar.fill",
             title: "Libretto e simulazione",
             detail: "Voti, media e crediti, con la simulazione di cosa succede alla media se il prossimo esame va in un certo modo."),
        Page(symbol: "door.left.hand.open",
             title: "Un'aula dove studiare",
             detail: "Quali aule sono libere adesso, in quale edificio e per quanto ancora. Dai dati pubblici del Politecnico, senza account."),
        Page(symbol: "square.grid.2x2.fill",
             title: "Senza aprire l'app",
             detail: "Widget con la prossima lezione e la media, controlli in Centro di Controllo e una Live Activity mentre sei in viaggio verso l'aula."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.brand.gradient)
                            .symbolRenderingMode(.hierarchical)
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .fontDesign(.rounded)
                            .multilineTextAlignment(.center)
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Accedi con account Polimi") {
                    // Explicit: the account route turns the sample data off,
                    // so nobody signs in and still reads invented lectures.
                    session.useMockData = false
                    advance()
                }

                Button {
                    session.useMockData = true
                    advance()
                } label: {
                    Text("Esplora con dati di esempio")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.brand)

                Text("PoliVerse non è un'app ufficiale del Politecnico di Milano. Le credenziali si inseriscono solo nella pagina di ateneo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Previews

#Preview("Benvenuto") {
    WelcomeStepView(advance: {}).previewEnvironment()
}

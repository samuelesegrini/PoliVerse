import SwiftUI
import WebKit

/// The personalised timetable the manifesto builds.
///
/// ## Why this shows the university's own page
///
/// The weekly grid is rendered server-side and the app cannot reproduce it
/// honestly: the slot cells are empty until the timetables for the year are
/// published, and for 2026/27 they were not, at the time this was written.
/// Parsing an empty grid into a SwiftUI calendar would produce a confident,
/// beautiful, blank week — which reads as a broken app rather than an
/// unpublished timetable.
///
/// So the cart is driven from inside the app — search, add, remove, clear, all
/// native — and the grid is shown as the Politecnico renders it, in the same
/// session. When the slots are published it will simply be full.
struct PersonalTimetableView: View {
    @Environment(ManifestiService.self) private var manifesti
    @AppStorage("manifestoSurname") private var surname = ""

    @State private var name = ""
    @State private var settingName = false
    @State private var showingGrid = false

    var body: some View {
        List {
            Section {
                TextField("Cognome e nome", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button {
                    Task {
                        settingName = true
                        await manifesti.setName(name)
                        surname = name.split(separator: " ").first.map(String.init) ?? name
                        settingName = false
                    }
                } label: {
                    if settingName {
                        ProgressView()
                    } else {
                        Label("Determina il mio scaglione", systemImage: "textformat.abc")
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || settingName)
            } header: {
                Text("Scaglione")
            } footer: {
                // The service's own warning, worth repeating because it
                // changes the answer.
                Text("Serve cognome **e** nome: con il solo cognome il Politecnico avverte che lo scaglione può risultare sbagliato.")
            }

            if let surname = manifesti.surname {
                Section {
                    LabeledContent("Impostato", value: surname)
                    LabeledContent("Insegnamenti", value: "\(manifesti.cartCount)")
                    Button {
                        showingGrid = true
                    } label: {
                        Label("Vedi l'orario settimanale", systemImage: "calendar")
                    }
                    Button(role: .destructive) {
                        Task { await manifesti.clearTimetable() }
                    } label: {
                        Label("Svuota l'orario", systemImage: "trash")
                    }
                } footer: {
                    Text("Aggiungi insegnamenti dalla loro scheda nel manifesto. L'orario personalizzato è uno strumento informale del Politecnico e non sostituisce il piano di studi.")
                }
            }
        }
        .navigationTitle("Orario personalizzato")
        .navigationBarTitleDisplayMode(.inline)
        .task { if name.isEmpty { name = surname } }
        .sheet(isPresented: $showingGrid) {
            NavigationStack {
                TimetableGridWeb(url: manifesti.timetableURL)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Orario")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Chiudi") { showingGrid = false }
                        }
                    }
            }
        }
    }
}

/// The grid, in the same cookie jar the cart was built in.
///
/// Shares `HTTPCookieStorage` with ``ManifestiService`` — a web view with its
/// own store would show an empty timetable, because the cart is server-side
/// state keyed to that cookie.
private struct TimetableGridWeb: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        Task { @MainActor in
            // Copied rather than shared: WKWebView keeps its own jar, and
            // without the session cookie the page renders an empty cart.
            let jar = HTTPCookieStorage.sharedCookieStorage(
                forGroupContainerIdentifier: "manifesti")
            for cookie in jar.cookies ?? [] where cookie.domain.contains("polimi.it") {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// MARK: - Previews

#Preview("Orario personalizzato") {
    PersonalTimetableView().previewInNavigation()
}

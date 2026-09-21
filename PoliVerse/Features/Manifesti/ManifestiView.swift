import SwiftUI

/// The course catalogue: search any teaching the Politecnico offers.
///
/// Not just the ones the student is enrolled in — this is the manifesto, so it
/// covers every degree course, every year, and the years before this one.
struct ManifestiView: View {
    @Environment(ManifestiModel.self) private var manifesti

    @State private var query = ""
    @State private var submitted = ""

    var body: some View {
        @Bindable var manifesti = manifesti

        List {
            Section {
                PageHero(symbol: "books.vertical", title: Text("Manifesto degli studi"), summary: Text("Corsi di studi, insegnamenti e schede"))
                    .listHeader()
            }
            Section {
                Picker("Anno accademico", selection: $manifesti.year) {
                    ForEach(AcademicYear.recent()) { year in
                        Text(year.label).tag(year)
                    }
                }
            } footer: {
                Text("Il manifesto è il catalogo ufficiale: programmi, docenti, scaglioni e bibliografia di tutti gli insegnamenti, anche quelli che non segui.")
            }
            .lookRow()

            if manifesti.isSearching && manifesti.results.isEmpty {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            if let message = manifesti.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .lookRow()
            }

            if !manifesti.results.isEmpty {
                Section("\(manifesti.results.count) insegnamenti") {
                    ForEach(manifesti.results) { teaching in
                        NavigationLink {
                            ManifestoDetailView(teaching: teaching)
                        } label: {
                            ManifestoRow(teaching: teaching)
                        }
                    }
                }
                .lookRow()
            }
            // Under the page's header rather than over it.
            if manifesti.results.isEmpty && !manifesti.isSearching {
                Section {
                    if submitted.isEmpty {
                        Text("Scrivi il nome di un insegnamento nel campo di ricerca e premi invio.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView.search(text: submitted)
                    }
                }
                .lookRow()
            }
        }
        .lookList()
        .navigationTitle("Manifesto")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Cerca un insegnamento")
        .onSubmit(of: .search) { runSearch() }
        // Warms the detail pages of what is on screen, so opening one is
        // instant — each is a page fetch and a parse.
        .prefetching(manifesti.results.map(\.id)) { ids in
            manifesti.prefetchDetails(manifesti.results.filter { ids.contains($0.id) })
        }
        .onChange(of: manifesti.year) { _, _ in
            if !submitted.isEmpty { runSearch() }
        }
    }

    private func runSearch() {
        submitted = query
        Task { await manifesti.search(query) }
    }
}

struct ManifestoRow: View {
    let teaching: ManifestoTeaching

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(teaching.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(teaching.code).monospaced()
                if let credits = teaching.credits {
                    Text("\(credits, format: .number) CFU")
                }
                if let course = teaching.degreeCourse {
                    Text(course).lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Previews

#Preview("Manifesto") {
    ManifestiView().previewInNavigation()
}

#Preview("Componente · Riga") {
    List {
        ManifestoRow(teaching: ManifestoTeaching(
            code: "086214", name: "METODI ANALITICI E NUMERICI PER L'INGEGNERIA",
            courseCode: "352", planCode: "E3N", idItemOfferta: nil, idRiga: nil,
            semester: "2", year: "2026", credits: 10,
            school: nil, degreeCourse: "(352) Ingegneria Energetica"))
    }
    .previewEnvironment()
}

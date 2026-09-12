import SwiftUI

/// The course catalogue: search any teaching the Politecnico offers.
///
/// Not just the ones the student is enrolled in — this is the manifesto, so it
/// covers every degree course, every year, and the years before this one.
struct ManifestiView: View {
    @Environment(ManifestiService.self) private var manifesti

    @State private var query = ""
    @State private var submitted = ""

    var body: some View {
        @Bindable var manifesti = manifesti

        List {
            Section {
                Picker("Anno accademico", selection: $manifesti.year) {
                    ForEach(AcademicYear.recent()) { year in
                        Text(year.label).tag(year)
                    }
                }
            } footer: {
                Text("Il manifesto è il catalogo ufficiale: programmi, docenti, scaglioni e bibliografia di tutti gli insegnamenti, anche quelli che non segui.")
            }

            if manifesti.isSearching && manifesti.results.isEmpty {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            if let message = manifesti.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
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
            }
        }
        .navigationTitle("Manifesto")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Cerca un insegnamento")
        .onSubmit(of: .search) { runSearch() }
        .overlay {
            if manifesti.results.isEmpty && !manifesti.isSearching {
                if submitted.isEmpty {
                    ContentUnavailableView(
                        "Cerca nel manifesto", systemImage: "books.vertical",
                        description: Text("Scrivi il nome di un insegnamento e premi invio."))
                } else {
                    ContentUnavailableView.search(text: submitted)
                }
            }
        }
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

private struct ManifestoRow: View {
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

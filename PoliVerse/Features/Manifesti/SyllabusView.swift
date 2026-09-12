import SwiftUI

/// The syllabus: objectives, learning outcomes, topics, prerequisites and the
/// books.
///
/// A different service again — `schedaincarico` — reached with the `c_classe`
/// the manifesto hides behind an icon. Public, and reachable directly: the
/// catalogue routes it through `aunicalogin`, but that only redirects to the
/// same page with two throwaway tokens, so the app skips the round trip.
struct SyllabusView: View {
    let classID: String
    let title: String

    @Environment(ManifestiService.self) private var manifesti
    @State private var syllabus: Syllabus?
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let syllabus, !syllabus.isEmpty {
                ForEach(syllabus.sections, id: \.title) { section in
                    Section(section.title) {
                        Text(section.body)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Section {
                    // Said plainly: many teachings simply have no published
                    // scheda, which is not the same as a failure.
                    Text("Il Politecnico non pubblica una scheda per questo modulo.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Programma")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            syllabus = await manifesti.syllabus(for: classID)
            loading = false
        }
    }
}

// MARK: - Previews

#Preview("Scheda insegnamento") {
    SyllabusView(classID: "889303", title: "Analisi numerica").previewInNavigation()
}

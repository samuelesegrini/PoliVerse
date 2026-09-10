import SwiftUI

/// WeBeep materials for one course, grouped by Moodle section.
struct CourseMaterialsView: View {
    let course: Course

    @Environment(Session.self) private var session
    @State private var service: WeBeepService?
    @State private var query = ""

    private var sections: [WeBeepSection] {
        guard let service else { return [] }
        guard !query.isEmpty else { return service.sections }
        return service.sections.compactMap { section in
            let matches = section.files.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : WeBeepSection(id: section.id, name: section.name, files: matches)
        }
    }

    var body: some View {
        List {
            if service?.isLive == false {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dati di esempio").font(.subheadline.weight(.semibold))
                            Text("Il collegamento a WeBeep non è ancora attivo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    }
                }
            }

            ForEach(sections) { section in
                Section(section.name) {
                    ForEach(section.files) { file in
                        FileRow(file: file, canDownload: service?.isLive == true)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Cerca nei materiali")
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if service?.isLoading == true {
                ProgressView()
            } else if sections.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task {
            let created = service ?? WeBeepService(session: session)
            service = created
            await created.loadMaterials(for: course)
        }
    }
}

private struct FileRow: View {
    let file: WeBeepFile
    /// Downloading is not wired up yet. Showing a download affordance that does
    /// nothing when tapped is worse than showing none, so it is hidden until
    /// the Moodle handshake lands.
    let canDownload: Bool
    // `Date.formatted` reads `Locale.current`, not the SwiftUI environment, so
    // the locale has to be threaded into the format style by hand.
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(2)
                Text("\(file.formattedSize) · \(file.modifiedAt.formatted(.relative(presentation: .named).locale(locale)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if canDownload {
                Image(systemName: file.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(file.isDownloaded ? .green : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

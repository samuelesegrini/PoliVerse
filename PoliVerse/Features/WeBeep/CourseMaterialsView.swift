import SwiftUI

/// WeBeep materials for one course, grouped by Moodle section.
struct CourseMaterialsView: View {
    let course: Course

    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var showingLogin = false

    private var sections: [WeBeepSection] {
        guard !query.isEmpty else { return weBeep.sections }
        return weBeep.sections.compactMap { section in
            let matches = section.files.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : WeBeepSection(id: section.id, name: section.name, files: matches)
        }
    }

    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    var body: some View {
        List {
            if needsLogin {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Collega WeBeep")
                            .font(.subheadline.weight(.semibold))
                        Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Accedi a WeBeep") { showingLogin = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            } else if session.useMockData {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dati di esempio").font(.subheadline.weight(.semibold))
                            Text("Disattiva i dati di esempio per usare WeBeep reale.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    }
                }
            }

            if case .failed(let message) = weBeep.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(sections) { section in
                Section(section.name) {
                    ForEach(section.files) { file in
                        FileRow(file: file) {
                            if let url = file.downloadURL { openURL(url) }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Cerca nei materiali")
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if weBeep.isLoadingMaterials {
                ProgressView()
            } else if sections.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if sections.isEmpty && !needsLogin {
                ContentUnavailableView("Nessun materiale", systemImage: "folder",
                                       description: Text("Questo corso non ha file pubblicati."))
            }
        }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet { await weBeep.loadMaterials(for: course) }
        }
        .task { await weBeep.loadMaterials(for: course) }
        .refreshable { await weBeep.loadMaterials(for: course) }
    }
}

private struct FileRow: View {
    let file: WeBeepFile
    let onOpen: () -> Void

    // `Date.formatted` reads `Locale.current`, not the SwiftUI environment, so
    // the locale has to be threaded into the format style by hand.
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: file.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text("\(file.formattedSize) · \(file.modifiedAt.formatted(.relative(presentation: .named).locale(locale)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if file.downloadURL != nil {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(file.downloadURL == nil)
    }
}

/// Wraps ``WeBeepLoginView`` in a dismissible sheet.
struct WeBeepLoginSheet: View {
    @Environment(WeBeepService.self) private var weBeep
    @Environment(CieIDRouter.self) private var cieID
    @Environment(\.dismiss) private var dismiss

    /// Run after a successful login, so the caller can refresh.
    let onSuccess: () async -> Void

    @State private var errorMessage: String?
    @State private var showingCieIDMissing = false

    var body: some View {
        NavigationStack {
            WeBeepLoginWebView(
                router: cieID,
                onToken: { token in
                    weBeep.store(token)
                    dismiss()
                    Task { await onSuccess() }
                },
                onError: { error in
                    errorMessage = error.localizedDescription
                },
                onCieIDMissing: { showingCieIDMissing = true }
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if cieID.isAwaitingCieID {
                    CieIDWaitingBanner()
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Accesso WeBeep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .alert("App CieID non installata", isPresented: $showingCieIDMissing) {
                Button("Apri App Store") { cieID.openAppStore() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Per accedere con la Carta d'Identità Elettronica serve l'app CieID.")
            }
        }
    }
}

/// Shown while the user is over in CieID, so returning to a seemingly idle
/// login page does not read as a failure.
struct CieIDWaitingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Completa l'accesso nell'app CieID, poi torna qui.")
                .font(.footnote)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

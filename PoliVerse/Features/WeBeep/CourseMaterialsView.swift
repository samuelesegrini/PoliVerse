import SwiftUI

/// WeBeep materials for one course, grouped by Moodle section: one card of
/// files per section, on the look in use, as Oggi draws its lists.
struct CourseMaterialsView: View {
    let course: Course

    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(FileDownloadService.self) private var downloads

    @State private var query = ""
    @State private var showingLogin = false
    @State private var previewURL: URL?

    private var sections: [WeBeepSection] {
        guard !query.isEmpty else { return weBeep.sections }
        return weBeep.sections.compactMap { section in
            let matches = section.files.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : WeBeepSection(id: section.id, name: section.name, files: matches)
        }
    }

    private var tint: Color { Theme.accent(for: course) }

    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    /// The kinds of file the course has, largest first, each with its colour.
    private var kinds: [MaterialKind] {
        let files: [WeBeepFile] = weBeep.sections.flatMap(\.files)
        let groups: [String: [WeBeepFile]] = Dictionary(grouping: files) { $0.icon }
        var totals: [(symbol: String, bytes: Int, count: Int)] = []
        for (symbol, members) in groups {
            let bytes = members.reduce(0) { $0 + $1.sizeBytes }
            totals.append((symbol, bytes, members.count))
        }
        totals.sort { $0.bytes == $1.bytes ? $0.count > $1.count : $0.bytes > $1.bytes }
        let colours = CourseRamp(course: course, style: style, scheme: scheme).colours(totals.count)
        var kinds: [MaterialKind] = []
        for (total, colour) in zip(totals, colours) {
            kinds.append(MaterialKind(symbol: total.symbol, bytes: total.bytes, count: total.count, colour: colour))
        }
        return kinds
    }

    var body: some View {
        let kinds = kinds
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if query.isEmpty, !needsLogin {
                    hero(kinds)
                }
                if needsLogin {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Collega WeBeep", systemImage: "books.vertical")
                            .font(.headline)
                        Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Accedi a WeBeep") { showingLogin = true }
                            .buttonStyle(.glassProminent)
                            .tint(tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .lookCard()
                } else if session.useMockData {
                    Label("Dati di esempio: disattivali per usare WeBeep reale.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                if case .failed(let message) = weBeep.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }

                ForEach(sections) { section in
                    sectionCard(section, kinds: kinds)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .courseScreen()
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
        .sheet(item: Binding(
            get: { previewURL.map(PreviewItem.init) },
            set: { previewURL = $0?.url }
        )) { item in
            NavigationStack {
                FilePreview(url: item.url)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { previewURL = nil }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: item.url)
                        }
                    }
            }
        }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet { await weBeep.loadMaterials(for: course) }
        }
        .task { await weBeep.loadMaterials(for: course) }
        .refreshable { await weBeep.loadMaterials(for: course) }
    }

    /// The kinds of file drawn as a pile, the largest in front, with how
    /// much there is in words and the proportion on a bar.
    @ViewBuilder
    private func hero(_ kinds: [MaterialKind]) -> some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        let files = weBeep.sections.flatMap(\.files)
        let downloaded = files.filter { if case .downloaded = downloads.status(for: $0) { true } else { false } }.count
        let bytes = Int64(kinds.reduce(0) { $0 + $1.bytes })
        VStack(spacing: 18) {
            CoursePageHero(
                tiles: [HeroTile(id: "folder", symbol: "folder", colour: ramp.main)],
                placeholder: HeroTile(id: "empty", symbol: "folder", colour: ramp.main),
                title: Text("Materiali"),
                summary: summary(files: files.count, bytes: bytes, downloaded: downloaded),
                badge: downloaded > 0 && downloaded == files.count
                    ? HeroBadge(symbol: "checkmark", tint: .green) : nil,
                mode: ramp.mode)
            if kinds.count > 1 {
                ShareBar(segments: kinds.prefix(5).map {
                    ShareBar.Segment(id: $0.symbol, title: MaterialKind.title($0.symbol), colour: $0.colour.color,
                                     value: Double(max($0.bytes, 1)))
                }, neutral: ramp.neutral.color)
                .padding(16)
                .lookCard()
            }
        }
    }

    /// "24 file · 1,2 GB · 3 offline".
    private func summary(files: Int, bytes: Int64, downloaded: Int) -> Text? {
        guard files > 0 else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return downloaded > 0 ? Text("\(files) file · \(size) · \(downloaded) offline") : Text("\(files) file · \(size)")
    }

    /// One Moodle section: its name and count, and its files on one card.
    private func sectionCard(_ section: WeBeepSection, kinds: [MaterialKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(verbatim: section.name) {
                Text("\(section.files.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(section.files) { file in
                    fileRow(file, colour: kinds.first { $0.symbol == file.icon }?.colour
                                ?? CourseRamp(course: course, style: style, scheme: scheme).main,
                            last: file.id == section.files.last?.id)
                }
            }
            .padding(.horizontal, style.material.hasCard ? 14 : 0)
            .padding(.vertical, style.material.hasCard ? 4 : 0)
            .lookCard()
        }
    }

    private func fileRow(_ file: WeBeepFile, colour: Flavor.RGB, last: Bool) -> some View {
        let status = downloads.status(for: file)
        return FileRow(colour: colour, file: file, status: status, last: last, onTap: { Task { await open(file) } })
            .contextMenu {
                if case .downloaded = status {
                    Button("Rimuovi il download", systemImage: "trash", role: .destructive) {
                        downloads.delete(file)
                    }
                }
            }
    }

    /// Downloads on first tap, previews thereafter.
    private func open(_ file: WeBeepFile) async {
        if case .downloaded(let url) = downloads.status(for: file) {
            previewURL = url
            return
        }
        if let url = await downloads.download(file) {
            previewURL = url
        }
    }
}

/// `sheet(item:)` needs an Identifiable; a bare URL is not.
private struct PreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// One kind of file on the page: what it weighs, how many, its colour.
struct MaterialKind {
    let symbol: String
    let bytes: Int
    let count: Int
    let colour: Flavor.RGB

    static func title(_ symbol: String) -> String {
        switch symbol {
        case "doc.richtext": String(localized: "PDF")
        case "doc.zipper": String(localized: "Archivi")
        case "play.rectangle": String(localized: "Video")
        case "rectangle.on.rectangle": String(localized: "Slide")
        case "doc.text": String(localized: "Documenti")
        case "tablecells": String(localized: "Tabelle")
        case "photo": String(localized: "Immagini")
        default: String(localized: "Altro")
        }
    }
}

private struct FileRow: View {
    let colour: Flavor.RGB
    let file: WeBeepFile
    let status: FileDownloadService.Status
    /// The last row of its card draws no hairline under it.
    var last = false
    let onTap: () -> Void

    // `Date.formatted` reads `Locale.current`, not the SwiftUI environment, so
    // the locale has to be threaded into the format style by hand.
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CourseRowTile(symbol: file.icon, colour: colour)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                        if case .failed(let message) = status {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        } else {
                            Text("\(file.formattedSize) · \(file.modifiedAt.formatted(.relative(presentation: .named).locale(locale)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 4)

                    switch status {
                    case .idle:
                        if file.downloadURL != nil {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        }
                    case .downloading(let progress):
                        ProgressView(value: progress > 0 ? progress : nil)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    case .downloaded:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 10)
                if !last {
                    Divider().padding(.leading, 42)
                }
            }
            .contentShape(.rect)
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
                    errorMessage = userFacingMessage(error)
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

// MARK: - Previews

#Preview("Materiali") {
    CourseMaterialsView(course: MockData.courses[0]).previewInNavigation()
}

#if os(macOS)
import QuickLook
import SwiftUI

/// Corsi on the Mac: the courses in a column, and the one selected beside it.
///
/// The iPhone opens a course as a page of its own; the Mac keeps the list in view and
/// shows the course next to it, its materials as a table first, since that is what a
/// student at a desk comes for, and everything else the iPhone's course page holds one
/// switch away.
struct MacCoursesView: View {
    @Environment(CourseModel.self) private var courses
    @Environment(UpdateFeed.self) private var feed
    @Environment(Session.self) private var session
    @Environment(WeBeepModel.self) private var weBeep

    /// The selected course's id.
    @State private var selectedID: Course.ID?
    /// Which half of the course is showing.
    @State private var page: Page = .materials
    /// Whether the WeBeep sign-in sheet is up.
    @State private var showingLogin = false

    /// The two halves of a course.
    enum Page: String, CaseIterable, Identifiable {
        /// The files, as a table.
        case materials
        /// The iPhone's course page: lessons, sittings, notices, forum, programme.
        case course

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .materials: "Materiali"
            case .course: "Corso"
            }
        }
    }

    /// WeBeep is where the list comes from: without it the list is empty for a reason
    /// the student can fix.
    private var needsLogin: Bool { !session.useMockData && !weBeep.isAuthenticated }

    private var visible: [Course] { courses.courses(in: courses.academicYears.first) .filter { !$0.isHidden } }
    private var selected: Course? { visible.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 380)
            Group {
                if let course = selected {
                    detail(course)
                } else if needsLogin {
                    login
                } else {
                    ContentUnavailableView("Scegli un corso", systemImage: "books.vertical",
                                           description: Text("I materiali e le novità compaiono qui."))
                }
            }
            .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(selected?.name ?? String(localized: "Corsi"))
        .navigationSubtitle(selected.map { "\($0.teacher) · \($0.cfu) CFU" } ?? "")
        .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
        .task { await courses.load() }
        .onChange(of: visible.map(\.id), initial: true) { _, ids in
            guard selectedID == nil || !ids.contains(selectedID!) else { return }
            selectedID = visible.max { unread(in: $0) < unread(in: $1) }?.id ?? ids.first
        }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet { await courses.load(force: true) }
                .macSheetSize(width: 560, height: 720)
        }
    }

    // MARK: - The list

    private var list: some View {
        let favourites = visible.filter(\.isFavourite)
        let others = visible.filter { !$0.isFavourite }
        return List(selection: $selectedID) {
            if !favourites.isEmpty {
                Section("Preferiti") {
                    ForEach(favourites) { row($0) }
                }
            }
            Section(favourites.isEmpty ? "I tuoi corsi" : "Tutti i corsi") {
                ForEach(others) { row($0) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if courses.isLoading && visible.isEmpty {
                ProgressView()
            } else if visible.isEmpty && !needsLogin {
                ContentUnavailableView("Nessun corso", systemImage: "books.vertical",
                                       description: Text("Non risultano corsi attivi su WeBeep."))
            }
        }
    }

    private func row(_ course: Course) -> some View {
        let count = unread(in: course)
        return HStack(spacing: 10) {
            Image(systemName: SubjectSymbol.symbol(for: course.name))
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent(for: course))
                .frame(width: 30, height: 30)
                .background(Theme.accent(for: course).opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(course.name).font(.callout.weight(.semibold)).lineLimit(2)
                Text(course.teacher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if course.isFavourite {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    .accessibilityLabel("Preferito")
            }
        }
        .padding(.vertical, 3)
        .badge(count)
        .tag(course.id)
        .contextMenu {
            Button(course.isFavourite ? "Togli dai preferiti" : "Aggiungi ai preferiti",
                   systemImage: course.isFavourite ? "star.slash" : "star") {
                courses.toggleFavourite(course)
            }
            Button("Nascondi", systemImage: "eye.slash") { courses.toggleHidden(course) }
        }
    }

    /// What is unread in a course.
    private func unread(in course: Course) -> Int {
        let badges = CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
        return badges.announcements + badges.materials + badges.exams
    }

    // MARK: - The course

    @ViewBuilder
    private func detail(_ course: Course) -> some View {
        VStack(spacing: 0) {
            header(course)
            switch page {
            case .materials:
                MacMaterialsTable(course: course)
            case .course:
                CourseDetailView(course: course)
            }
        }
        .id(course.id)
    }

    /// The course in its colour, and the switch between its materials and the rest.
    private func header(_ course: Course) -> some View {
        let tint = Theme.accent(for: course)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text([course.code, "\(course.cfu) CFU", course.semester.isEmpty ? nil : course.semester]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(tint)
                    Text(course.name).font(.title.weight(.bold)).lineLimit(2)
                    Text(course.teacher).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("Sezione", selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
    }

    private var login: some View {
        ContentUnavailableView {
            Label("Collega WeBeep", systemImage: "books.vertical")
        } description: {
            Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
        } actions: {
            Button("Accedi a WeBeep") { showingLogin = true }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Materials

/// One course's WeBeep files as a table: sortable by name, section, kind, size and
/// date; a double click or Return opens a file, the space bar previews it with Quick
/// Look, and the context menu reaches the Finder.
struct MacMaterialsTable: View {
    /// The course whose files these are.
    let course: Course

    @Environment(Session.self) private var session
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(FileDownloadModel.self) private var downloads

    @State private var selection = Set<MaterialRow.ID>()
    @State private var sortOrder = [KeyPathComparator(\MaterialRow.modifiedAt, order: .reverse)]
    @State private var query = ""
    /// The file Quick Look is showing.
    @State private var quickLook: URL?

    /// One file, as the table reads it.
    nonisolated struct MaterialRow: Identifiable, Sendable {
        let file: WeBeepFile
        /// The kind's name, worked out once on the main actor.
        let kind: String
        var id: String { file.id }
        var name: String { file.name }
        var section: String { file.sectionName }
        var size: Int { file.sizeBytes }
        var modifiedAt: Date { file.modifiedAt }
    }

    private var allFiles: [WeBeepFile] { weBeep.sections.flatMap(\.files) }

    private var rows: [MaterialRow] {
        let files = query.isEmpty ? allFiles : allFiles.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.sectionName.localizedCaseInsensitiveContains(query)
        }
        return files.map { MaterialRow(file: $0, kind: MaterialKind.title($0.icon)) }.sorted(using: sortOrder)
    }

    private var selectedFiles: [WeBeepFile] { allFiles.filter { selection.contains($0.id) } }

    /// The downloaded copies, for Quick Look to page through.
    private var downloadedURLs: [URL] {
        allFiles.compactMap { if case .downloaded(let url) = downloads.status(for: $0) { url } else { nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.file.icon)
                            .foregroundStyle(Theme.accent(for: course))
                            .frame(width: 18)
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        statusMark(for: row.file)
                    }
                    .help(row.name)
                }
                .width(min: 220, ideal: 360)
                TableColumn("Sezione", value: \.section) { Text($0.section).foregroundStyle(.secondary) }
                    .width(min: 100, ideal: 160)
                TableColumn("Tipo", value: \.kind) { Text($0.kind).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 80)
                TableColumn("Dimensione", value: \.size) { row in
                    Text(row.file.formattedSize).monospacedDigit().foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Modificato", value: \.modifiedAt) { row in
                    Text(row.modifiedAt, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 120)
            }
            .contextMenu(forSelectionType: MaterialRow.ID.self) { ids in
                menu(for: allFiles.filter { ids.contains($0.id) })
            } primaryAction: { ids in
                for file in allFiles where ids.contains(file.id) { Task { await open(file) } }
            }
            .onKeyPress(.space) {
                guard let file = selectedFiles.first else { return .ignored }
                Task { await preview(file) }
                return .handled
            }
            .quickLookPreview($quickLook, in: downloadedURLs)
            .overlay { overlay }

            Divider()
            footer
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Cerca nei materiali")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Quick Look", systemImage: "eye") {
                    if let file = selectedFiles.first { Task { await preview(file) } }
                }
                .disabled(selectedFiles.isEmpty)
                .help("Anteprima (Spazio)")
                Button("Scarica", systemImage: "arrow.down.circle") {
                    for file in selectedFiles { Task { _ = await downloads.download(file) } }
                }
                .disabled(selectedFiles.allSatisfy { !canDownload($0) })
                Button("Mostra nel Finder", systemImage: "folder") { reveal(selectedFiles) }
                    .disabled(selectedFiles.allSatisfy { localURL(of: $0) == nil })
            }
        }
        .task(id: course.id) { await weBeep.loadMaterials(for: course) }
    }

    @ViewBuilder
    private var overlay: some View {
        if weBeep.isLoadingMaterials && allFiles.isEmpty {
            ProgressView()
        } else if rows.isEmpty && !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if allFiles.isEmpty && !weBeep.isLoadingMaterials {
            ContentUnavailableView("Nessun materiale", systemImage: "folder",
                                   description: Text("Questo corso non ha file pubblicati."))
        }
    }

    /// "47 file · 128 MB · 3 scaricati".
    private var footer: some View {
        let bytes = Int64(allFiles.reduce(0) { $0 + $1.sizeBytes })
        let downloaded = downloadedURLs.count
        return HStack(spacing: 14) {
            Text("\(allFiles.count) file · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
            if downloaded > 0 { Text("\(downloaded) scaricati") }
            if session.useMockData { Text("Dati di esempio") }
            Spacer()
            if case .failed(let message) = weBeep.state {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    @ViewBuilder
    private func statusMark(for file: WeBeepFile) -> some View {
        switch downloads.status(for: file) {
        case .idle:
            EmptyView()
        case .downloading(let progress):
            ProgressView(value: progress > 0 ? progress : nil)
                .progressViewStyle(.circular)
                .controlSize(.mini)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Scaricato")
        case .failed(let message):
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                .help(message)
        }
    }

    @ViewBuilder
    private func menu(for files: [WeBeepFile]) -> some View {
        if !files.isEmpty {
            Button("Apri", systemImage: "arrow.up.forward.app") {
                for file in files { Task { await open(file) } }
            }
            Button("Quick Look", systemImage: "eye") {
                if let file = files.first { Task { await preview(file) } }
            }
            if files.contains(where: canDownload) {
                Button("Scarica", systemImage: "arrow.down.circle") {
                    for file in files { Task { _ = await downloads.download(file) } }
                }
            }
            let local = files.compactMap(localURL)
            if !local.isEmpty {
                Button("Mostra nel Finder", systemImage: "folder") { reveal(files) }
                ShareLink(items: local) { Label("Condividi", systemImage: "square.and.arrow.up") }
                Divider()
                Button("Rimuovi il download", systemImage: "trash", role: .destructive) {
                    for file in files { downloads.delete(file) }
                }
            }
            if files.count == 1, let url = files.first?.downloadURL {
                Divider()
                Button("Copia il link", systemImage: "link") { Clipboard.copy(url.absoluteString) }
            }
        }
    }

    // MARK: - Actions

    private func localURL(of file: WeBeepFile) -> URL? {
        if case .downloaded(let url) = downloads.status(for: file) { url } else { nil }
    }

    private func canDownload(_ file: WeBeepFile) -> Bool {
        file.downloadURL != nil && localURL(of: file) == nil
    }

    /// Downloads when needed, then opens the file in its own app.
    private func open(_ file: WeBeepFile) async {
        if let url = await ensureLocal(file) { NSWorkspace.shared.open(url) }
    }

    /// Downloads when needed, then shows the file in Quick Look.
    private func preview(_ file: WeBeepFile) async {
        if let url = await ensureLocal(file) { quickLook = url }
    }

    private func ensureLocal(_ file: WeBeepFile) async -> URL? {
        if let url = localURL(of: file) { return url }
        return await downloads.download(file)
    }

    private func reveal(_ files: [WeBeepFile]) {
        let urls = files.compactMap(localURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

#Preview("Corsi") {
    NavigationStack { MacCoursesView() }
        .previewEnvironment()
        .frame(width: 1100, height: 760)
}
#endif

import Foundation
import SwiftUI

/// What the app is holding, what kind of thing it is, and what can go.
///
/// Built the way Impostazioni ▸ iCloud ▸ Gestisci spazio is, because that
/// screen answers the question people actually arrive with. It does three
/// things in order, and each one answers the previous one's "…of what?":
///
/// 1. **A picture of the biggest thing.** The largest kind of file is drawn
///    as one big icon with the runners-up tucked behind it, sized in
///    proportion. Before a single number is read, the screen has already said
///    "it's the recordings" — which for this app is nearly always the true
///    answer and nearly never the one a student guesses.
/// 2. **One bar.** The proportion, done, instead of a column of byte counts
///    the reader has to compare in their head.
/// 3. **The rows**, largest first, each with the way to remove it.
///
/// The old version of this screen showed two numbers — cache and materials —
/// which answers "how much" and nothing else. "400 MB di materiali" is not
/// something anyone can act on; "four lecture recordings" is.
struct DataStorageView: View {
    /// The shared ``DataStatus``, from the environment.
    @Environment(DataStatus.self) private var status
    /// The shared ``FreshnessCoordinator``, from the environment.
    @Environment(FreshnessCoordinator.self) private var freshness
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The look the student chose, so this screen is painted in it rather than
    /// in colours of its own.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// What the last scan found, largest kind first.
    @State private var categories: [StorageAudit.Category] = []
    /// True once a scan has finished, so an empty page is not shown as an empty disk.
    @State private var hasScanned = false
    /// True while a scan is running.
    @State private var isRefreshing = false
    /// The kind whose deletion is being confirmed, if any.
    @State private var confirmingDeletion: StorageAudit.Category?
    /// Whether deleting every downloaded material is being confirmed.
    @State private var confirmingMaterials = false

    /// The kinds that are downloaded WeBeep files, which can be fetched again.
    private var materials: [StorageAudit.Category] { categories.filter(\.kind.isMaterial) }
    /// What the app itself is holding: caches and offline records.
    private var appData: StorageAudit.Category? { categories.first { !$0.kind.isMaterial } }

    /// The view's content.
    var body: some View {
        let palette = FileKindPalette(style: style, scheme: scheme, categories: categories)
        List {
            Section {
                StorageHero(categories: categories, hasScanned: hasScanned, palette: palette)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                StorageBar(categories: categories, palette: palette)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .lookRow()

            if !materials.isEmpty {
                Section {
                    ForEach(materials) { category in
                        StorageCategoryRow(category: category, palette: palette)
                            .swipeActions {
                                Button("Elimina", systemImage: "trash", role: .destructive) {
                                    confirmingDeletion = category
                                }
                            }
                    }
                    Button("Elimina tutti i materiali", role: .destructive) {
                        confirmingMaterials = true
                    }
                } header: {
                    Text("Materiali scaricati")
                } footer: {
                    Text("File aperti da WeBeep e tenuti per leggerli offline. Restano su WeBeep: si riscaricano quando li riapri.")
                }
                .lookRow()
            }

            Section {
                if let appData {
                    StorageCategoryRow(category: appData, palette: palette)
                } else if hasScanned {
                    // A zero row rather than a missing section: the reader came
                    // here to find out where the space went, and a section that
                    // silently vanishes reads as something being hidden.
                    StorageCategoryRow(
                        category: .init(kind: .appData, bytes: 0, fileCount: 0, urls: []),
                        palette: palette)
                }
                Button("Svuota cache") { clearAppData() }
                    .disabled(appData == nil)
            } header: {
                Text("Dati dell’app")
            } footer: {
                Text("Orari, corsi e carriera, per aprire l’app senza rete. Si ricostruisce da sola al prossimo aggiornamento: niente di tuo viene perso.")
            }
            .lookRow()

            // The account of what the line at the bottom of the screen
            // summarises: which service, how old, and what failed.
            Section {
                // The same sentence as the line at the bottom of the screen:
                // a student who came here *because* of that line must find it
                // again, not a list of services that all say "Mai" with no
                // explanation of why.
                if status.badge != nil {
                    Label(String(localized: status.summary), systemImage: status.symbol)
                        .font(.subheadline)
                        // The masks are a multicolour symbol: left alone they
                        // arrive in their own orange and white and read as a
                        // sticker rather than as part of the sentence.
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.orange)
                }
                ForEach(freshness.services) { service in
                    ServiceFreshnessRow(service: service)
                }
                Button {
                    isRefreshing = true
                    status.clearFailures()
                    Task {
                        await freshness.revalidate(force: true)
                        isRefreshing = false
                    }
                } label: {
                    LabeledContent {
                        if isRefreshing { ProgressView() }
                    } label: {
                        Text("Aggiorna adesso")
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Aggiornamenti")
            } footer: {
                Text("L’app aggiorna da sola quando la apri e quando torna la connessione.")
            }
            .lookRow()
        }
        .lookList()
        .navigationTitle("Dati e archiviazione")
        // Inline, as on the profile page: the picture is the headline here,
        // and a large title above it pushes the tiles off the first screen.
        .navigationBarTitleDisplayMode(.inline)
        // Measured on appearance, not at init: the view is built once and
        // shown again after a download, and a size from last week is worse
        // than no size at all.
        .task { await measure() }
        .animation(.snappy(duration: 0.35), value: categories)
        .confirmationDialog(
            confirmingDeletion.map { Text("Eliminare \($0.kind.title.lowercased())?") } ?? Text(""),
            isPresented: Binding(get: { confirmingDeletion != nil },
                                 set: { if !$0 { confirmingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: confirmingDeletion
        ) { category in
            Button("Elimina", role: .destructive) {
                StorageAudit.delete(category)
                Task { await measure() }
            }
        } message: { category in
            Text("\(category.fileCount) file, \(formattedBytes(category.bytes)). Restano su WeBeep.")
        }
        .confirmationDialog("Eliminare tutti i materiali scaricati?",
                            isPresented: $confirmingMaterials, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                FileDownloadModel.clearStorage()
                Task { await measure() }
            }
        } message: {
            Text("\(formattedBytes(categories.materialBytes)) di file. Restano su WeBeep.")
        }
    }

    /// Scans the disk and publishes what it found.
    private func measure() async {
        categories = await StorageAudit.scan()
        hasScanned = true
    }

    /// Cleared through the stores rather than by removing their files, so each
    /// one gets to drop whatever it is holding in memory as well — an
    /// `OfflineStore` whose folder disappears underneath it would keep serving
    /// records this screen has just claimed to have deleted.
    private func clearAppData() {
        DiskCache.clear()
        OfflineStore.shared.clearAll()
        Task { await measure() }
    }
}

// MARK: - The picture at the top

/// The biggest kind of file in front, with the runners-up behind it, sized by
/// their bytes. The arrangement and the glass are ``HeroTileStack``'s, shared
/// with the other settings pages.
struct StorageHero: View {
    /// The kinds to draw, largest first.
    let categories: [StorageAudit.Category]
    /// Before the first scan there is nothing to draw and nothing to say.
    var hasScanned = true
    /// The colour each kind is drawn in.
    let palette: FileKindPalette

    /// The view's content.
    var body: some View {
        HeroTileStack(
            tiles: categories.map {
                HeroTile(id: $0.kind.rawValue, symbol: $0.kind.symbol,
                         colour: palette.rgb($0.kind), weight: Double($0.bytes))
            },
            placeholder: HeroTile(id: "empty", symbol: "externaldrive", colour: palette.rgb(nil)),
            showsPlaceholder: hasScanned,
            mode: palette.mode)
    }
}

/// One kind of file as a solid icon, for the rows.
struct FileKindTile: View {
    /// The kind of file, or `nil` for the app's own data.
    let kind: StorageAudit.Kind?
    /// The tile's side, in points.
    let side: CGFloat
    /// The colour this kind is drawn in.
    let palette: FileKindPalette

    /// The view's content.
    var body: some View {
        GlassTile(symbol: kind?.symbol ?? "externaldrive", colour: palette.rgb(kind), side: side)
    }
}

/// The colour of every tile, dot and bar segment on this page: a
/// ``FlavorRamp`` handed out by size, so the largest kind is the deepest and
/// the smallest the palest — a second reading of the bar. The cost is that a
/// kind's colour can change after a deletion; the symbol, not the colour, says
/// what a tile is.
struct FileKindPalette {
    /// The look's ramp the colours are taken from.
    private let ramp: FlavorRamp
    /// One colour per kind, handed out in order of size.
    private let tints: [StorageAudit.Kind: Flavor.RGB]

    /// How the look asks its surfaces to be drawn.
    var mode: Flavor.Mode { ramp.mode }

    /// The palette for one scan.
    ///
    /// - Parameters:
    ///   - style: The look in use.
    ///   - scheme: Light or dark.
    ///   - categories: The kinds found, largest first.
    init(style: TodayStyle, scheme: ColorScheme, categories: [StorageAudit.Category]) {
        ramp = FlavorRamp(style: style, scheme: scheme)
        tints = Dictionary(uniqueKeysWithValues: zip(categories.map(\.kind), ramp.colours(categories.count)))
    }

    /// A kind's colour.
    ///
    /// - Parameter kind: The kind, or `nil` for the app's own data.
    /// - Returns: Its colour, or the ramp's neutral.
    func rgb(_ kind: StorageAudit.Kind?) -> Flavor.RGB {
        kind.flatMap { tints[$0] } ?? ramp.neutral
    }

    /// A kind's colour, as a SwiftUI colour.
    ///
    /// - Parameter kind: The kind, or `nil` for the app's own data.
    /// - Returns: Its colour.
    func tint(_ kind: StorageAudit.Kind?) -> Color { rgb(kind).color }

    /// The fold-in segment and its dot, and the empty track.
    var neutral: Color { ramp.neutral.color }
}

// MARK: - The bar

/// Every kind in proportion, with the percentages under it.
///
/// Capped at five segments and a remainder, as iCloud's is: past that the
/// slivers are too thin to see and the legend wraps to four lines, and a
/// reader who wants the sixth kind's exact size has the rows below.
private struct StorageBar: View {
    /// The kinds to put in proportion, largest first.
    let categories: [StorageAudit.Category]
    /// The colour each segment is drawn in.
    let palette: FileKindPalette

    /// One stretch of the bar.
    private struct Segment: Identifiable {
        /// The segment's identity.
        let id: String
        /// What the segment is called in the legend.
        let title: String
        /// The segment's colour.
        let tint: Color
        /// What it takes, in bytes.
        let bytes: Int
    }

    /// Everything the scan found, added up.
    private var total: Int { categories.totalBytes }

    /// The five largest kinds, plus everything else folded into one.
    private var segments: [Segment] {
        let shown = categories.prefix(5).map {
            Segment(id: $0.kind.rawValue, title: $0.kind.title,
                    tint: palette.tint($0.kind), bytes: $0.bytes)
        }
        let rest = categories.dropFirst(5).totalBytes
        guard rest > 0 else { return shown }
        return shown + [Segment(id: "rest", title: String(localized: "Altro"),
                                tint: palette.neutral, bytes: rest)]
    }

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                HStack(spacing: total > 0 ? 2 : 0) {
                    ForEach(segments) { segment in
                        // A floor of a few points, so a kind that holds
                        // something is never drawn as nothing at all.
                        segment.tint
                            .frame(width: max(6, geometry.size.width
                                              * CGFloat(segment.bytes) / CGFloat(max(total, 1))))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 12)
                // Empty, a grey track rather than nothing: the section keeps
                // its height when the first file lands.
                .background(palette.neutral.opacity(0.28), in: .capsule)
                .clipShape(.capsule)
            }
            .frame(height: 12)

            if total > 0 {
                LegendFlow(spacing: 14, rowSpacing: 6) {
                    ForEach(segments) { segment in
                        HStack(spacing: 5) {
                            Circle().fill(segment.tint).frame(width: 8, height: 8)
                            Text("\(segment.title) \(percent(segment.bytes))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Text(total > 0
                 ? "In tutto \(formattedBytes(total)) su questo dispositivo."
                 : "L’app non sta occupando spazio su questo dispositivo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(total > 0
                                 ? "In tutto \(formattedBytes(total)). \(spokenBreakdown)"
                                 : "L’app non sta occupando spazio su questo dispositivo."))
    }

    /// Rounded to whole points, and never to zero: "0%" beside a kind the row
    /// below says is 3 MB is the screen contradicting itself.
    ///
    /// Formatted rather than concatenated with a literal "%": the sign's
    /// placement and spacing differ by locale, and in Turkish it leads.
    private func percent(_ bytes: Int) -> String {
        guard total > 0 else { return 0.formatted(.percent) }
        let share = Double(bytes) / Double(total)
        return max(0.01, (share * 100).rounded() / 100)
            .formatted(.percent.precision(.fractionLength(0)))
    }

    /// The bar read out as kinds and percentages, for assistive technologies.
    private var spokenBreakdown: String {
        segments.map { "\($0.title) \(percent($0.bytes))" }.joined(separator: ", ")
    }
}

/// Lays the legend out in as many chips as fit per line, wrapping the rest.
///
/// A fixed column count would leave "Fogli di calcolo 4%" beside "PDF 36%" in
/// a grid sized for the longest, which is most of a line of whitespace at
/// larger text sizes. Ten lines of `Layout` are cheaper than that.
private struct LegendFlow: Layout {
    /// The gap between two chips on a line.
    var spacing: CGFloat
    /// The gap between two lines.
    var rowSpacing: CGFloat

    /// The height the chips need at the proposed width.
    ///
    /// - Parameters:
    ///   - proposal: The size offered.
    ///   - subviews: The chips.
    ///   - cache: Unused.
    /// - Returns: The size taken.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(of: subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    /// Places each chip on its line, centred vertically within it.
    ///
    /// - Parameters:
    ///   - bounds: The room to fill.
    ///   - proposal: The size offered.
    ///   - subviews: The chips.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    /// One line of chips and the height it needs.
    private struct Row {
        /// Which chips are on this line.
        var indices: [Int] = []
        /// The tallest chip on it.
        var height: CGFloat = 0
    }

    /// Breaks the chips into lines that fit.
    ///
    /// - Parameters:
    ///   - subviews: The chips, in order.
    ///   - width: The room on one line.
    /// - Returns: The lines.
    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - The rows

/// One kind: its icon, how many files it is, and what it takes.
private struct StorageCategoryRow: View {
    /// The kind this row is about.
    let category: StorageAudit.Category
    /// The colour its tile is drawn in.
    let palette: FileKindPalette

    /// The view's content.
    var body: some View {
        // Hand-built rather than a `LabeledContent`: with a two-line label
        // that pushes its value onto a third line, under the subtitle, where
        // it reads as part of the description instead of as the size.
        HStack(spacing: 12) {
            FileKindTile(kind: category.kind, side: 30, palette: palette)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.kind.title)
                Text(category.fileCount == 1 ? "1 file" : "\(category.fileCount) file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formattedBytes(category.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One service, and when it last had something to show for itself.
private struct ServiceFreshnessRow: View {
    /// The service this row is about, with when it last answered.
    let service: FreshnessCoordinator.ServiceStatus

    /// The view's content.
    var body: some View {
        LabeledContent {
            if service.failure != nil {
                Label("Non riuscito", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let age = service.age {
                Text(Date.now.addingTimeInterval(-age), format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Mai")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(service.title)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sizes, with the numbers kept as numbers: `ByteCountFormatter` renders an
/// empty store as "Zero KB", which reads as a fault rather than as a store
/// with nothing in it.
func formattedBytes(_ count: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(count))
}

// MARK: - Previews

#Preview("Dati e archiviazione") {
    NavigationStack { DataStorageView() }.previewEnvironment()
}

/// The same storage under four looks, which is the whole point of deriving the
/// tiles from the Flavor: the picture has to hold together in a student's own
/// colour, not only in the one it was designed against.
#Preview("Il disegno in alto") {
    @Previewable @Environment(\.colorScheme) var scheme

    let sample: [StorageAudit.Category] = [
        .init(kind: .video, bytes: 3_200_000_000, fileCount: 7, urls: []),
        .init(kind: .pdf, bytes: 1_400_000_000, fileCount: 212, urls: []),
        .init(kind: .presentation, bytes: 420_000_000, fileCount: 38, urls: []),
        .init(kind: .appData, bytes: 90_000_000, fileCount: 24, urls: []),
        .init(kind: .image, bytes: 12_000_000, fileCount: 61, urls: []),
    ]

    ScrollView {
        VStack(spacing: 24) {
            ForEach(["#0F3D6E", "#E8751A", "#2FA88A", "#5B6472"], id: \.self) { hex in
                var style = TodayStyle()
                let _ = { style.flavor = Flavor(hex: hex) ?? .polimi }()
                let palette = FileKindPalette(style: style, scheme: scheme, categories: sample)
                VStack(spacing: 8) {
                    Text(style.flavor.name).font(.caption).foregroundStyle(.secondary)
                    StorageHero(categories: sample, palette: palette)
                }
            }
            StorageHero(categories: [],
                        palette: FileKindPalette(style: TodayStyle(), scheme: scheme, categories: []))
        }
        .padding(.vertical, 24)
    }
}

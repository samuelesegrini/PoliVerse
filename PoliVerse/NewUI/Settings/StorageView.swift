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
    @Environment(DataStatus.self) private var status
    @Environment(FreshnessCoordinator.self) private var freshness
    @Environment(\.colorScheme) private var scheme

    /// The look the student chose, so this screen is painted in it rather than
    /// in colours of its own.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    @State private var categories: [StorageAudit.Category] = []
    @State private var hasScanned = false
    @State private var isRefreshing = false
    @State private var confirmingDeletion: StorageAudit.Category?
    @State private var confirmingMaterials = false

    private var materials: [StorageAudit.Category] { categories.filter(\.kind.isMaterial) }
    private var appData: StorageAudit.Category? { categories.first { !$0.kind.isMaterial } }

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
        }
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
                FileDownloadService.clearStorage()
                Task { await measure() }
            }
        } message: {
            Text("\(formattedBytes(categories.materialBytes)) di file. Restano su WeBeep.")
        }
    }

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

/// The biggest thing on the device, drawn big, with the runners-up behind it.
///
/// The arrangement is the one iCloud's storage screen uses, and it works for
/// the same reason: an icon is recognised before a label is read, so the
/// screen has answered "what is taking the space" before the eye reaches the
/// bar. The difference is that iCloud has app icons to show and this has file
/// kinds, so the tiles are built — a squircle, a colour, a symbol — to read as
/// icons rather than as a legend that floated up the page.
///
/// The four corners are copied from that screen rather than invented, and what
/// makes them work is that **nothing about them is symmetric**: the tiles are
/// four different sizes, the leading pair is bigger than the trailing pair, and
/// the bottom pair hangs lower than the top pair rides high. Four equal squares
/// at four equal offsets read as a diagram of a cross; this reads as a pile of
/// icons, which is the thing being drawn.
struct StorageHero: View {
    let categories: [StorageAudit.Category]
    /// Before the first scan there is nothing to draw and nothing to say —
    /// the placeholder would flash for a frame and read as "empty".
    var hasScanned = true
    let palette: FileKindPalette

    /// Scaled, so the picture grows with the reader's text rather than staying
    /// a postage stamp beside a headline they have turned up to Accessibility
    /// sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 112

    private var hero: StorageAudit.Category? { categories.first }
    private var satellites: [StorageAudit.Category] { Array(categories.dropFirst().prefix(4)) }

    /// One corner, with the height and the size that corner wants — all three
    /// measured off the reference, in units of the hero's side.
    private struct Slot {
        /// Which side of the hero: leading or trailing.
        let x: CGFloat
        /// How far above or below the hero's centre the tile sits. The two
        /// numbers below the hero are larger than the two above it, which is
        /// the asymmetry that keeps the group from reading as a cross.
        let y: CGFloat
        /// The size this position wants before the bytes have their say.
        /// Strictly decreasing, so the four are never the same square.
        let scale: CGFloat
    }

    /// Filled in rank order: the second-largest kind takes the big top-leading
    /// corner, where the eye starts, and the fifth takes the small one.
    private static let slots: [Slot] = [
        Slot(x: -1, y: -0.38, scale: 0.62),
        Slot(x: -1, y: 0.46, scale: 0.52),
        Slot(x: 1, y: -0.32, scale: 0.44),
        Slot(x: 1, y: 0.50, scale: 0.41),
    ]

    /// How much of a runner-up disappears behind the hero, as a fraction of
    /// *its own* side — the proportion the reference keeps at every size.
    /// Measured from the hero's edge rather than from a fixed centre: a fixed
    /// centre leaves a gap behind a small tile and swallows a large one whole.
    private static let tuck: CGFloat = 0.18

    var body: some View {
        ZStack {
            if let hero {
                ForEach(Array(satellites.enumerated()), id: \.element.id) { index, category in
                    let slot = Self.slots[index]
                    let satellite = side * scale(of: category, against: hero, in: slot)
                    FileKindTile(kind: category.kind, side: satellite, palette: palette, surface: .tintedGlass)
                        .offset(x: slot.x * (side / 2 + satellite * (0.5 - Self.tuck)),
                                y: slot.y * side)
                }
                FileKindTile(kind: hero.kind, side: side, palette: palette, surface: .glass)
            } else {
                FileKindTile(kind: nil, side: side, palette: palette, surface: .glass)
                    .opacity(hasScanned ? 1 : 0)
            }
        }
        // Tall enough for the lowest corner at its largest: 0.5 down plus half
        // a tile, on both sides of the hero.
        .frame(height: side * 1.6)
        .animation(.snappy(duration: 0.4), value: categories)
        // Decorative: every kind in it is named, with its size, in the rows
        // below, and a VoiceOver reader has no use for "a picture of them".
        .accessibilityHidden(true)
    }

    /// How big a runner-up is drawn: what its bytes ask for, met halfway with
    /// what its corner asks for.
    ///
    /// Bytes alone are the honest answer and the wrong picture. Real storage on
    /// this app is lopsided — a term of recordings against a handful of PDFs —
    /// so strictly proportional tiles collapse into one big square and three
    /// identical specks, which is exactly the monotony the arrangement exists
    /// to avoid. Two things fix it. The fourth root rather than the square root
    /// spreads the tail, so a kind at a tenth of the hero draws at 56% instead
    /// of 32%; the geometric mean with the corner's own size then guarantees
    /// the four are visibly different even when the data is extreme, while a
    /// second place that is genuinely large still grows into the space.
    ///
    /// This is the picture, not the measurement: the exact sizes are in the
    /// rows below, where nothing is rounded in anyone's favour.
    private func scale(of category: StorageAudit.Category,
                       against hero: StorageAudit.Category, in slot: Slot) -> CGFloat {
        guard hero.bytes > 0, category.bytes > 0 else { return slot.scale }
        let ratio = CGFloat(category.bytes) / CGFloat(hero.bytes)
        let byBytes = min(1, pow(ratio, 0.25)) * 0.68
        return (byBytes * slot.scale).squareRoot()
    }
}

/// One kind of file as an app icon would be: a squircle, a colour, a symbol.
///
/// `nil` is the empty device — the same shape in grey, so the screen keeps its
/// height and its shape when the last file goes and does not appear to have
/// lost a section.
struct FileKindTile: View {
    /// What the tile is made of.
    enum Surface {
        /// A filled squircle with a black or white symbol: the small icon in a
        /// row, where it has to read at 30 points on a white card.
        case solid
        /// Liquid Glass tinted with the kind's colour, as Oggi's sections are
        /// in the Vetro tinto material, with the symbol in that colour.
        case tintedGlass
        /// Plain Liquid Glass with the symbol carrying the colour as a
        /// gradient: the front tile of the hero, which should read as an
        /// object rather than as a swatch.
        case glass
    }

    let kind: StorageAudit.Kind?
    let side: CGFloat
    let palette: FileKindPalette
    var surface: Surface = .solid

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
    }

    var body: some View {
        switch surface {
        case .solid:
            shape
                .fill(palette.tint(kind).gradient)
                .frame(width: side, height: side)
                .overlay { symbol(size: 0.42).foregroundStyle(palette.glyph(kind)) }
                // The tiles overlap, so each needs an edge of its own: without
                // the shadow they read as one torn shape.
                .shadow(color: .black.opacity(0.22), radius: side * 0.08, y: side * 0.04)
        case .tintedGlass:
            Color.clear
                .frame(width: side, height: side)
                // The modifier Oggi's sections use, fed a Flavor made of this
                // kind's colour: the same glass, the same tint strength, so
                // the storage screen and the home screen are visibly one app.
                .todayMaterial(.tintedGlass, flavor: Flavor(main: palette.rgb(kind)),
                               mode: palette.mode, cornerRadius: side * 0.2237)
                .overlay { symbol(size: 0.46).symbolVariant(.fill).foregroundStyle(palette.tint(kind)) }
        case .glass:
            Color.clear
                .frame(width: side, height: side)
                .todayMaterial(.glass, flavor: palette.flavor, mode: palette.mode,
                               cornerRadius: side * 0.2237)
                .overlay { symbol(size: 0.5).foregroundStyle(palette.gradient(kind)) }
                // The glass alone is nearly the colour of the page; a soft
                // lift is what separates it from the tinted tiles behind it.
                .shadow(color: .black.opacity(0.12), radius: side * 0.1, y: side * 0.05)
        }
    }

    private func symbol(size: CGFloat) -> some View {
        Image(systemName: kind?.symbol ?? "externaldrive")
            .font(.system(size: side * size, weight: .medium))
    }
}

/// The colour of every tile, dot and bar segment on this screen, derived from
/// the look the student chose.
///
/// The first version of this used system colours — a red PDF, a green
/// spreadsheet — on the theory that the Files app has already taught everyone
/// which is which. It was wrong for *this* app: PoliVerse lets a student pick
/// a Flavor and then paints the whole of Oggi with it, and a storage screen
/// that ignores that choice reads as a page borrowed from somewhere else.
///
/// So the colours are a ramp built **from** the Flavor, and a kind's place on
/// it is its **place in this scan**: the largest is the deepest, the smallest
/// the palest, the way iCloud's bar steps from dark to light green. Two
/// earlier versions gave each kind a fixed colour instead, and both failed the
/// same way — ten kinds from one hue leave neighbours a shade apart, and the
/// bar happened to put the near-twins side by side. Spreading only the kinds
/// actually present gives them the whole ramp between them, and "deeper means
/// bigger" is a second reading of the bar rather than an arbitrary code. The
/// cost is that a kind's colour can change after a deletion; the symbol, not
/// the colour, is what says what a tile is.
///
/// A colourful Flavor gives a narrow hue ramp; a grey one gives a lightness
/// ramp only, because spreading hues around a grey would invent a colour the
/// student deliberately did not pick — the refusal ``Flavor/derived`` makes.
///
/// Built once per render rather than per tile: each colour walks a contrast
/// loop to clear the page it sits on.
struct FileKindPalette {
    let flavor: Flavor
    let mode: Flavor.Mode
    private let tints: [StorageAudit.Kind: Flavor.RGB]
    private let empty: Flavor.RGB

    /// How much of the colour wheel the ramp covers, centred on the Flavor's
    /// hue. A sixth: roughly the span of "blues". Half the wheel was tried
    /// first and turned a navy look into a green PDF and a purple archive.
    private static let spread = 0.16

    init(style: TodayStyle, scheme: ColorScheme, categories: [StorageAudit.Category]) {
        flavor = style.flavor
        mode = style.appearance.flavorMode
        let dark = scheme == .dark
        let ground = flavor.ground(dark: dark, mode: mode)
        let (hue, saturation, _) = flavor.main.hsb
        // The threshold ``Flavor/derived`` uses to decide a colour has no hue
        // worth moving along.
        let isGrey = saturation < 0.12

        /// Nudges a colour until it clears the page, the way
        /// ``Flavor/readable(_:dark:mode:)`` does for the roles: a dark look
        /// would otherwise draw near-black marks on a near-black ground.
        func visible(_ colour: Flavor.RGB) -> Flavor.RGB {
            var candidate = colour
            var (hue, saturation, brightness) = colour.hsb
            var steps = 0
            while Flavor.contrast(candidate, ground) < Flavor.readable, steps < 40 {
                brightness = dark ? min(brightness + 0.04, 1) : max(brightness - 0.04, 0)
                candidate = Flavor.RGB(hue: hue, saturation: saturation, brightness: brightness)
                steps += 1
            }
            return candidate
        }

        var tints: [StorageAudit.Kind: Flavor.RGB] = [:]
        for (index, category) in categories.enumerated() {
            let position = categories.count > 1 ? Double(index) / Double(categories.count - 1) : 0
            tints[category.kind] = visible(Flavor.RGB(
                hue: isGrey ? hue : hue + Self.spread * (position - 0.5),
                // Floored, so a washed-out Flavor still gives marks that read;
                // capped, so a fluorescent one does not glare.
                saturation: isGrey ? saturation : saturation.clamped(to: 0.40...0.95),
                // Its own lightness range rather than the Flavor's: a deep
                // navy look would otherwise give every kind a near-black.
                brightness: 0.48 + 0.42 * position))
        }
        self.tints = tints
        // Nothing measured: the Flavor with the colour taken out, so the
        // placeholder is plainly not one of the kinds.
        empty = visible(Flavor.RGB(hue: hue, saturation: saturation * 0.12,
                                   brightness: dark ? 0.42 : 0.72))
    }

    func rgb(_ kind: StorageAudit.Kind?) -> Flavor.RGB {
        kind.flatMap { tints[$0] } ?? empty
    }

    func tint(_ kind: StorageAudit.Kind?) -> Color { rgb(kind).color }

    /// Black or white on a solid tile, whichever reads — the choice
    /// ``Flavor/onAccent(dark:mode:)`` makes, per tile because the ramp runs
    /// from deep to pale and a fixed white would vanish at one end.
    func glyph(_ kind: StorageAudit.Kind?) -> Color {
        let tile = rgb(kind)
        return Flavor.contrast(.white, tile) >= Flavor.contrast(.black, tile)
            ? Flavor.RGB.white.color : Flavor.RGB.black.color
    }

    /// The front tile's symbol: lit from the top corner and deepening towards
    /// the bottom, so the outline reads as a material rather than a flat ink.
    /// Outline and not `.fill` on the front tile: on untinted glass a filled
    /// glyph turns into a solid slab that fights the glass for attention, and
    /// the tiles behind already carry the filled weight.
    func gradient(_ kind: StorageAudit.Kind?) -> LinearGradient {
        let (hue, saturation, brightness) = rgb(kind).hsb
        let light = Flavor.RGB(hue: hue, saturation: saturation * 0.6, brightness: min(brightness + 0.32, 1))
        let deep = Flavor.RGB(hue: hue, saturation: min(saturation * 1.1, 1), brightness: brightness * 0.68)
        return LinearGradient(colors: [light.color, deep.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The fold-in segment and its dot, and the empty track.
    var neutral: Color { empty.color }
}

// MARK: - The bar

/// Every kind in proportion, with the percentages under it.
///
/// Capped at five segments and a remainder, as iCloud's is: past that the
/// slivers are too thin to see and the legend wraps to four lines, and a
/// reader who wants the sixth kind's exact size has the rows below.
private struct StorageBar: View {
    let categories: [StorageAudit.Category]
    let palette: FileKindPalette

    private struct Segment: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let bytes: Int
    }

    private var total: Int { categories.totalBytes }

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
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(of: subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

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

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

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
    let category: StorageAudit.Category
    let palette: FileKindPalette

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
    let service: FreshnessCoordinator.ServiceStatus

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

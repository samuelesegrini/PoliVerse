import PhotosUI
import SwiftUI

/// A page of Personalizza's panel: one part of the look.
enum CustomizePage: Hashable, Identifiable {
    case flavor, paper, decoration, cards, appearance, widget, accessory, layout, greeting, bar
    case section(TodaySection.Kind)
    /// The emoji keyboard, pushed from the accessory page rather than
    /// presented over the panel.
    case stickerPicker

    var id: String {
        switch self {
        case .section(let kind): "section-\(kind.rawValue)"
        default: String(describing: self)
        }
    }

    /// The page for a zone tapped on the page.
    init(zone: TodayLanding.Zone) {
        switch zone {
        case .bar: self = .bar
        case .greeting: self = .greeting
        case .date: self = .widget
        case .stickers: self = .accessory
        case .background: self = .flavor
        case .section(let kind): self = .section(kind)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .flavor: "Flavor"
        case .paper: "Carta"
        case .decoration: "Decorazione"
        case .cards: "Superficie"
        case .appearance: "Aspetto"
        case .widget: "Data"
        case .accessory: "Accessorio"
        case .layout: "Sezioni"
        case .greeting: "Saluto"
        case .bar: "Barra"
        case .section(let kind): kind.title
        case .stickerPicker: "Aggiungi sticker"
        }
    }
}

/// The controls of one panel page: a curated set and one fine control.
struct CustomizeControls: View {
    let page: CustomizePage
    @Binding var style: TodayStyle
    @Binding var arranging: Bool
    var pickStickers: () -> Void = {}
    /// Back to the bento, after a change that empties the page.
    var close: () -> Void = {}

    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var scheme
    @State private var photoItem: PhotosPickerItem?
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Form {
            switch page {
            case .flavor: flavorControls
            case .paper: paperControls
            case .decoration: decorationControls
            case .cards: cardControls
            case .appearance: appearanceControls
            case .widget: dateControls
            case .accessory: accessoryControls
            case .layout: layoutControls
            case .greeting: greetingControls
            case .bar: barControls
            case .section(let kind): sectionControls(kind)
            case .stickerPicker: EmptyView()
            }
        }
        // Changes reach the page as they are made: the back button is the
        // only way out, and the editor's Fine the only save.
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Flavor

    @ViewBuilder
    private var flavorControls: some View {
        Section {
            FlavorFlowView(flavor: style.flavor)
                .frame(height: 110)
                .clipShape(.rect(cornerRadius: 22))
                .overlay {
                    VStack(spacing: 2) {
                        Text(style.flavor.name).font(.title2.weight(.bold))
                        Text("Flavor").font(.caption2.weight(.semibold)).opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            HStack(spacing: 10) {
                ForEach(Flavor.Role.allCases, id: \.self) { role in
                    FlavorRoleSwatch(role: role, flavor: $style.flavor)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Colori")
        } footer: {
            Text("Scelti da soli a partire dal principale: tocca un colore per cambiarlo.")
        }
        Section {
            FlavorRow(flavor: $style.flavor)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Colori da una foto", systemImage: "photo")
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let flavor = Flavor.extract(from: image.samplePixels()) {
                        withAnimation(.snappy) { style.flavor = flavor }
                    }
                    photoItem = nil
                }
            }
            Button("Colori suggeriti", systemImage: "wand.and.sparkles") {
                withAnimation(.snappy) { style.flavor.resetDerived() }
            }
        }
        Section {
            ShareLink(item: style.flavor.shareCode, subject: Text("Flavor \(style.flavor.name)")) {
                Label("Condividi il Flavor", systemImage: "square.and.arrow.up")
            }
            PasteButton(payloadType: String.self) { strings in
                guard let flavor = strings.lazy.compactMap(Flavor.init(shareCode:)).first else { return }
                Task { @MainActor in withAnimation(.snappy) { style.flavor = flavor } }
            }
        } footer: {
            Text("Un Flavor condiviso è un codice: incollalo qui per usarlo.")
        }
    }

    // MARK: Paper

    @ViewBuilder
    private var paperControls: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(TodayPaper.allCases) { paper in
                    Button { style.paper = paper } label: {
                        PaperTile(paper: paper, style: style, selected: style.paper == paper)
                            .frame(height: 120)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(paper.title))
                    .accessibilityIdentifier("paper-\(paper.rawValue)")
                    .accessibilityAddTraits(style.paper == paper ? .isSelected : [])
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            Slider(value: $style.grain, in: 0...1) {
                Text("Grana")
            } minimumValueLabel: {
                Image(systemName: "circle")
            } maximumValueLabel: {
                Image(systemName: "circle.dotted")
            }
            .accessibilityIdentifier("paper-grain")
        } header: {
            Text("Grana")
        } footer: {
            Text("Una grana di pellicola su tutta la pagina.")
        }
    }

    // MARK: Decoration

    private var decorationControls: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TodayBackground.allCases) { background in
                    Button { style.background = background } label: {
                        VStack(spacing: 6) {
                            TodayBackgroundView(background: background, flavor: style.flavor, paper: style.paper,
                                                mode: style.appearance.flavorMode)
                                .frame(height: 96)
                                .clipShape(.rect(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(style.background == background ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                                      lineWidth: style.background == background ? 2.5 : 1)
                                }
                            Text(background.title)
                                .font(.caption)
                                .foregroundStyle(style.background == background ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style.background == background ? .isSelected : [])
                }
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("Il motivo prende il colore del Flavor.")
        }
    }

    // MARK: Cards

    private var cardControls: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(TodayMaterial.allCases) { material in
                    Button { style.material = material } label: {
                        VStack(spacing: 6) {
                            MaterialPreview(material: material, style: style)
                                .frame(height: 64)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(style.material == material ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
                                }
                            Text(material.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(style.material == material ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(material.title))
                    .accessibilityIdentifier("material-\(material.rawValue)")
                    .accessibilityAddTraits(style.material == material ? .isSelected : [])
                }
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("Ogni sezione può averne uno suo.")
        }
    }

    // MARK: Appearance

    @ViewBuilder
    private var appearanceControls: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(TodayAppearance.allCases) { appearance in
                    Button { style.appearance = appearance } label: {
                        VStack(spacing: 6) {
                            AppearanceTile(appearance: appearance, style: style)
                                .frame(height: 86)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(style.appearance == appearance ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                                      lineWidth: style.appearance == appearance ? 3 : 1)
                                }
                            Text(appearance.title)
                                .font(.caption.weight(style.appearance == appearance ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(appearance.rawValue)")
                    .accessibilityAddTraits(style.appearance == appearance ? .isSelected : [])
                }
            }
            .listRowBackground(Color.clear)
        }
        Section("Testo") {
            Picker("Testo", selection: $style.textDesign) {
                ForEach(TodayStyle.TextDesign.allCases) { design in
                    Text(design.title).fontDesign(design.design).tag(design)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Bar

    private var barControls: some View {
        Section {
            Toggle("Profilo", isOn: $style.bar.showsProfile)
            Toggle("Giorno", isOn: $style.bar.showsDate)
        } header: {
            Text("Pulsanti")
        } footer: {
            Text("Impostazioni e Personalizza restano sempre nella barra: sono la strada per tornarci.")
        }
    }

    // MARK: Accessory

    @ViewBuilder
    private var accessoryControls: some View {
        Section {
            Picker("Accanto alla data", selection: $style.accessory) {
                ForEach(TodayAccessory.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("date-header-layout")
        } footer: {
            Text("Con un accessorio la data occupa metà della larghezza.")
        }
        switch style.accessory {
        case .none:
            EmptyView()
        case .stickers:
            Section {
                ForEach(style.stickers) { sticker in
                    HStack(spacing: 12) {
                        StickerContentView(content: sticker.content)
                            .frame(width: 36, height: 36)
                        Text(sticker.content.isEmoji ? "Emoji" : "Sticker")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { style.stickers[$0].id }
                    ids.forEach { style.removeSticker($0) }
                }
                Button("Aggiungi sticker", systemImage: "plus", action: pickStickers)
                    .disabled(style.stickers.count >= TodayStyle.maxStickers)
                    .accessibilityIdentifier("sticker-controls-add")
                Toggle("Bordo bianco", isOn: $style.stickerOutline)
            } header: {
                Text("Sticker")
            } footer: {
                Text("Tieni premuto sulla pagina per spostarli, ingrandirli e ruotarli.")
            }
        case .text:
            Section {
                TextField("Tutto pronto?", text: $style.accessoryText)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("accessory-text")
            } header: {
                Text("Testo")
            } footer: {
                Text("Poche parole, nel carattere della data e nel colore del Flavor.")
            }
        case .photos:
            Section {
                ForEach(style.photoIDs, id: \.self) { id in
                    StickerContentView(content: .image(id), fill: true)
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .onDelete { offsets in
                    let ids = offsets.map { style.photoIDs[$0] }
                    ids.forEach { style.removePhoto($0) }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: TodayStyle.maxPhotos, matching: .images) {
                    Label("Scegli le foto", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: photoItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let resized = UIImage(data: data)?.resizedJPEG(maxSide: 900),
                               let id = try? StickerStore.shared.save(resized) {
                                withAnimation(.snappy) { style.addPhoto(id) }
                            }
                        }
                        photoItems = []
                    }
                }
            } header: {
                Text("Foto")
            } footer: {
                Text("Fino a tre, impilate come stampe.")
            }
        }
    }

    // MARK: Layout

    @ViewBuilder
    private var layoutControls: some View {
        Section {
            ForEach(style.visibleSections) { section in
                Label(section.kind.title, systemImage: section.kind.systemImage)
            }
            .onMove { offsets, destination in
                let visible = style.visibleSections
                let moved = offsets.map { visible[$0].kind }
                let target = destination < visible.count ? visible[destination].kind : nil
                withAnimation(.snappy) { style.moveSections(moved, before: target) }
            }
            .onDelete { offsets in
                let visible = style.visibleSections
                offsets.map { visible[$0].kind }.forEach { style.hideSection($0) }
            }
        } header: {
            Text("Sulla pagina")
        }
        .environment(\.editMode, .constant(.active))
        Section("Ogni sezione") {
            ForEach(style.visibleSections) { section in
                NavigationLink(value: CustomizePage.section(section.kind)) {
                    Label(section.kind.title, systemImage: section.kind.systemImage)
                }
                .accessibilityIdentifier("layout-section-\(section.kind.rawValue)")
            }
        }
        if !style.addableSections.isEmpty {
            Section("Aggiungi") {
                ForEach(style.addableSections) { kind in
                    Button { withAnimation(.snappy) { style.addSection(kind) } } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            }
        }
        Section {
            Button("Disponi sulla pagina", systemImage: "square.stack.3d.up") {
                withAnimation(.snappy) { arranging = true }
            }
            .accessibilityIdentifier("customize-editor-arrange")
        } footer: {
            Text("Oppure tieni premuto sulla pagina per trascinare le sezioni.")
        }
    }

    // MARK: Sections

    private func section(_ kind: TodaySection.Kind) -> Binding<TodaySection> {
        Binding {
            style.section(kind) ?? TodaySection(kind: kind)
        } set: { new in
            style.updateSection(kind) { $0 = new }
        }
    }

    @ViewBuilder
    private func sectionControls(_ kind: TodaySection.Kind) -> some View {
        let section = section(kind)
        Section("Superficie") {
            Picker("Superficie", selection: section.material) {
                Text("Come la pagina").tag(TodayMaterial?.none)
                ForEach(TodayMaterial.allCases) { Text($0.title).tag(TodayMaterial?.some($0)) }
            }
            .accessibilityIdentifier("section-material")
            Picker("Densità", selection: section.density) {
                ForEach(TodaySection.Density.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Colore del Flavor", isOn: section.tinted)
            if kind.hasCourseColours {
                Toggle("Colori dei corsi", isOn: section.courseColours)
            }
        }
        if kind.listsItems {
            Section {
                Stepper(value: section.itemLimit, in: TodaySection.itemLimits) {
                    Text("Elementi mostrati: \(section.wrappedValue.itemLimit)")
                }
            }
        }
        Section {
            Button("Nascondi dalla pagina", systemImage: "eye.slash", role: .destructive) {
                style.hideSection(kind)
                close()
            }
        } footer: {
            Text("Una sezione nascosta tiene le sue impostazioni.")
        }
    }

    // MARK: Greeting

    @ViewBuilder
    private var greetingControls: some View {
        Section {
            Toggle("Mostra il saluto", isOn: $style.showsGreeting)
        }
        Section("Stile") {
            ForEach(GreetingStyle.allCases) { greeting in
                Button { style.greeting = greeting } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting.title).font(.subheadline.weight(.medium))
                            Text(greeting.text(for: .now, firstName: session.student?.firstName, custom: style.customGreeting))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if style.greeting == greeting {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!style.showsGreeting)
                .accessibilityIdentifier("greeting-\(greeting.rawValue)")
            }
            if style.greeting == .custom {
                TextField("Scrivi il tuo saluto", text: $style.customGreeting)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            }
        }
    }

    // MARK: Date

    private var dateLayoutControls: some View {
        Section("Forma") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(DateLayout.allCases) { layout in
                        Button { style.dateLayout = layout } label: {
                            VStack(spacing: 6) {
                                DateHeader(day: .now, style: { var preview = style; preview.dateLayout = layout; preview.dateAlignment = .leading; return preview }(), size: 30)
                                    .padding(10)
                                    .frame(width: 150, height: 86, alignment: .leading)
                                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(style.dateLayout == layout ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
                                    }
                                Text(layout.title).font(.caption)
                                    .foregroundStyle(style.dateLayout == layout ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(style.dateLayout == layout ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            Picker("Allineamento", selection: $style.dateAlignment) {
                ForEach(DateAlignment.allCases) { alignment in
                    Image(systemName: alignment.systemImage).tag(alignment)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var dateControls: some View {
        dateLayoutControls
        Section("Carattere") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(TodayStyle.DateFont.allCases) { font in
                    Button { style.dateFont = font } label: {
                        Text("15")
                            .font(font.font(size: 28, weight: style.dateWeight))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(style.dateFont == font ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                        in: .rect(cornerRadius: 14))
                            .overlay {
                                if style.dateFont == font {
                                    RoundedRectangle(cornerRadius: 14).strokeBorder(.tint, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(font.title))
                    .accessibilityIdentifier("date-font-\(font.rawValue)")
                    .accessibilityAddTraits(style.dateFont == font ? .isSelected : [])
                }
            }
            Slider(value: $style.dateWeight, in: 0...1) {
                Text("Spessore")
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "bold")
            }
            Slider(value: $style.dateSize, in: TodayStyle.dateSizes) {
                Text("Grandezza")
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger")
            }
        }
        Section("Colore") {
            Picker("Colore", selection: $style.dateColour) {
                ForEach(TodayStyle.DateColour.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Pieces

/// One of a Flavor's three colours, with the system picker over it.
private struct FlavorRoleSwatch: View {
    let role: Flavor.Role
    @Binding var flavor: Flavor
    @Environment(\.self) private var environment

    private var label: LocalizedStringKey {
        switch role {
        case .main: "PRINCIPALE"
        case .accent: "ACCENTO"
        case .extra: "EXTRA"
        }
    }

    var body: some View {
        let colour = flavor.colour(role)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colour.color)
            .frame(height: 76)
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Flavor.contrast(.white, colour) >= Flavor.contrast(.black, colour) ? Color.white : Color.black)
                    .padding(.bottom, 8)
            }
            .overlay {
                // The system picker, nearly invisible, over the whole swatch.
                ColorPicker(selection: binding, supportsOpacity: false) { Text(label) }
                    .labelsHidden()
                    .scaleEffect(3)
                    .opacity(0.02)
            }
            .accessibilityIdentifier("flavor-role-\(role.rawValue)")
    }

    private var binding: Binding<Color> {
        Binding {
            flavor.colour(role).color
        } set: { colour in
            let resolved = colour.resolve(in: environment)
            let rgb = Flavor.RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
            switch role {
            case .main: flavor.base = rgb
            case .accent: flavor.accentColour = rgb
            case .extra: flavor.extraColour = rgb
            }
        }
    }
}

/// The system's colour picker for any colour, then the Flavor swatches.
private struct FlavorRow: View {
    @Binding var flavor: Flavor
    @Environment(\.self) private var environment

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ColorPicker("Altro colore", selection: pickerColour, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("flavor-picker")
                ForEach(Flavor.swatches) { swatch in
                    Button { withAnimation(.snappy) { flavor = swatch.flavor } } label: {
                        Circle()
                            .fill(swatch.flavor.base.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if flavor.hex == swatch.flavor.hex {
                                    Circle().strokeBorder(.background, lineWidth: 3).padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(swatch.name))
                    .accessibilityIdentifier("flavor-\(swatch.flavor.hex)")
                    .accessibilityAddTraits(flavor.hex == swatch.flavor.hex ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var pickerColour: Binding<Color> {
        Binding {
            flavor.base.color
        } set: { colour in
            let resolved = colour.resolve(in: environment)
            flavor = Flavor(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }
    }
}

/// A material on the look's background, with a line of text and an accent.
struct MaterialPreview: View {
    let material: TodayMaterial
    let style: TodayStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TodayBackgroundView(style: style)
            .overlay {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(style.accent(scheme)).frame(width: 18, height: 4)
                    Capsule().fill(.primary.opacity(0.6)).frame(width: 26, height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(7)
                .todayMaterial(material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: 9)
                .padding(8)
            }
            .clipShape(.rect(cornerRadius: 14))
    }
}

/// A sheet of paper with its bottom corner peeled up, as Kyo shows materials.
struct PaperTile: View {
    let paper: TodayPaper
    let style: TodayStyle
    var selected = false
    var showsTitle = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 8, bottomTrailingRadius: 16,
                                           topTrailingRadius: 16, style: .continuous)
        TodayBackgroundView(background: .plain, flavor: style.flavor, paper: paper, grain: style.grain,
                            mode: style.appearance.flavorMode)
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                PeeledCorner(colour: style.flavor.ground(dark: scheme == .dark, mode: style.appearance.flavorMode).color)
                    .frame(width: 44, height: 44)
            }
            .overlay(alignment: .bottomTrailing) {
                if showsTitle {
                    Text(paper.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.accent(scheme))
                        .padding(10)
                }
            }
            .overlay {
                shape.strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: selected ? 3 : 1)
            }
    }
}

/// A folded corner: the back of the sheet, and the white beneath.
private struct PeeledCorner: View {
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                }
                .fill(.white)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(to: CGPoint(x: size.width, y: size.height),
                                      control: CGPoint(x: size.width * 0.95, y: size.height * 0.05))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                }
                .fill(LinearGradient(colors: [colour, colour.opacity(0.7)], startPoint: .topTrailing, endPoint: .bottomLeading))
                .shadow(color: .black.opacity(0.18), radius: 4, x: 2, y: -2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An appearance drawn as a small page: the date and a card.
private struct AppearanceTile: View {
    let appearance: TodayAppearance
    let style: TodayStyle

    var body: some View {
        switch appearance {
        case .system:
            HStack(spacing: 0) {
                page(dark: false)
                page(dark: true)
            }
            .clipShape(.rect(cornerRadius: 18))
        case .light, .contrast, .tinted:
            page(dark: false).clipShape(.rect(cornerRadius: 18))
        case .dark:
            page(dark: true).clipShape(.rect(cornerRadius: 18))
        }
    }

    private func page(dark: Bool) -> some View {
        let mode = appearance.flavorMode
        let ground = style.flavor.ground(dark: dark, mode: mode).color
        let surface = style.flavor.surface(dark: dark, mode: mode).color
        let ink: Color = dark ? .white : .black
        return ZStack(alignment: .topLeading) {
            ground
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(ink.opacity(0.85)).frame(width: 28, height: 6)
                Capsule().fill(style.flavor.accent(dark: dark, mode: mode).color).frame(width: 18, height: 4)
                RoundedRectangle(cornerRadius: 6).fill(surface).frame(height: 28)
            }
            .padding(10)
        }
    }
}

private extension PlacedSticker.Content {
    var isEmoji: Bool {
        if case .emoji = self { true } else { false }
    }
}

extension UIImage {
    /// A small grid of the image's colours, for picking a Flavor from it.
    func samplePixels(side: Int = 40) -> [Flavor.RGB] {
        guard let cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).compactMap { index in
            guard bytes[index + 3] > 128 else { return nil }
            return Flavor.RGB(red: Double(bytes[index]) / 255, green: Double(bytes[index + 1]) / 255,
                              blue: Double(bytes[index + 2]) / 255)
        }
    }

    /// A JPEG no larger than a side, for photos kept beside the date.
    func resizedJPEG(maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).jpegData(withCompressionQuality: 0.85) { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

import PhotosUI
import SwiftUI

extension LookTool {
    /// What the tool's group is called in the inspector; none where its
    /// controls carry their own name, as the rulers do.
    var inspectorTitle: LocalizedStringKey? {
        switch self {
        case .grain, .dimensions: nil
        case .dateColour: "Colore della data"
        case .dateShape: "Forma della data"
        default: title
        }
    }

    /// A line under the tool's controls, where they need one.
    var note: LocalizedStringKey? {
        switch self {
        case .photo: "Principale e accento vengono dai suoi colori."
        case .light: "Tinto colora lo sfondo; Contrasto rende testo e bordi più netti."
        default: nil
        }
    }
}

/// One tool's controls, as the design draws them: tiles, chips, rulers,
/// swatches or cards, in a row under the page on iPhone and in a grid in the
/// inspector on iPad and Mac.
struct LookToolView: View {
    /// The tool.
    let tool: LookTool
    /// The look being edited.
    @Binding var look: TodayStyle
    /// Where the tool is drawn.
    let layout: ToolLayout
    /// The sticker selected on the page.
    @Binding var selectedSticker: UUID?
    /// How the Home Screen previewed for App draws its icons.
    @Binding var homeLook: AppPreview.HomeLook
    /// Whether the page is in arranging mode.
    @Binding var arranging: Bool
    /// Opens the sticker keyboard.
    let pickStickers: () -> Void
    /// Starts one of the iPhone's tasks: writing a greeting or the words beside
    /// the date, or placing the stickers. `nil` where the tools edit in place,
    /// as the inspector does.
    var enterMode: ((EditorMode) -> Void)?
    /// Set while one of the tools' text fields has the keyboard.
    var typing: Binding<Bool> = .constant(false)

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    @State private var photoItem: PhotosPickerItem?
    @State private var photoItems: [PhotosPickerItem] = []
    /// The section whose settings are open in Sezioni.
    @State private var openSection: TodaySection.Kind?
    /// One of the text fields has the keyboard.
    @FocusState private var fieldFocused: Bool

    /// The look as drawn.
    private var drawn: TodayStyle { look.resolved }

    /// The lights, in the order the design offers them.
    private static let lights: [TodayAppearance] = [.system, .light, .tinted, .contrast, .dark]

    /// The view's content.
    var body: some View {
        Group {
            switch tool {
            case .classics: classics
            case .specials: specials
            case .photo: photo
            case .main: main
            case .accent: accent
            case .light: light
            case .paper: paper
            case .motif: motif
            case .grain: grain
            case .typeface: typeface
            case .dimensions: dimensions
            case .dateColour: dateColour
            case .dateShape: dateShape
            case .greeting: greeting
            case .beside: beside
            case .surface: surface
            case .sections: sections
            case .appIcon: appIcon
            case .appTint: padded { AppTintPicker(look: $look, layout: layout == .strip ? .row : .grid(columns: 6)) }
            case .appBar: padded { AppBarPicker(look: $look) }
            case .special: EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool-\(tool.id)")
    }

    /// Controls that bring no padding of their own, lined up with the rows.
    private func padded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, layout == .strip ? 18 : 0)
            .padding(.vertical, 4)
    }

    /// A note under a strip's controls.
    @ViewBuilder
    private func stripNote(_ note: LocalizedStringKey) -> some View {
        Text(note)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, layout == .strip ? 18 : 0)
    }

    // MARK: - Tema

    /// Casuale, set apart, then the classic themes.
    private var classics: some View {
        ToolRow(layout: layout, minimum: ThemeTile.size.width + 4) {
            SurpriseTile(look: $look)
                .padding(.trailing, layout == .strip ? 10 : 0)
            ForEach(Array(TodayStyle.presets.enumerated()), id: \.offset) { index, theme in
                ThemeTile(look: $look, theme: theme, caption: Text(theme.displayName(at: index)))
                    .accessibilityIdentifier("theme-preset-\(index)")
            }
        }
    }

    /// The special Flavors, each marked.
    private var specials: some View {
        ToolRow(layout: layout, minimum: ThemeTile.size.width + 4) {
            ForEach(SpecialFlavor.allCases) { special in
                ThemeTile(look: $look, theme: .starting(special), caption: Text(special.title), special: true)
                    .accessibilityIdentifier("theme-special-\(special.rawValue)")
            }
        }
    }

    /// A photo to take the colours from.
    private var photo: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Scegli una foto", systemImage: "photo.on.rectangle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("theme-photo")
            if layout == .strip, let note = tool.note { stripNote(note) }
        }
        .padding(.horizontal, layout == .strip ? 18 : 0)
        .padding(.vertical, 6)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = PlatformImage(data: data),
                   let flavor = Flavor.extract(from: image.samplePixels()) {
                    withAnimation(.snappy) {
                        look.flavor = flavor
                        // A special Flavor keeps its own page: only the colour comes from the photo.
                        if look.special == nil {
                            look.appearance = .tinted
                            look.background = .mesh
                        }
                    }
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Colore

    /// The main colour: the swatches, and every other colour in the grid.
    private var main: some View {
        SwatchRow(layout: layout, current: look.flavor.base, gridTitle: "Colore principale") { colour in
            withAnimation(.snappy) { look.flavor.base = colour }
        }
    }

    /// The accent: Automatico, which follows the main colour, then the swatches.
    private var accent: some View {
        var derived = look.flavor
        derived.resetDerived()
        let automatic = look.flavor.accentIsDerived
        return SwatchRow(layout: layout, current: automatic ? nil : look.flavor.accentColour, gridTitle: "Colore d’accento",
                         pick: { colour in withAnimation(.snappy) { look.flavor.accentColour = colour } },
                         automatic: (derived.accentColour, automatic, { withAnimation(.snappy) { look.flavor.resetDerived() } }))
    }

    /// The five lights, each with a dot of its page and its ink.
    private var light: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipRow(layout: layout) {
                ForEach(Self.lights) { appearance in
                    let dark = appearance.colorScheme == .dark
                    let ground = look.flavor.ground(dark: dark, mode: appearance.flavorMode).color
                    let ink: Color = dark ? .white : .black
                    ToolChip(title: Text(appearance.title),
                             dot: AnyShapeStyle(LinearGradient(stops: [.init(color: ground, location: 0.5), .init(color: ink, location: 0.5)],
                                                               startPoint: .leading, endPoint: .trailing)),
                             chosen: look.appearance == appearance) {
                        withAnimation(.snappy) { look.appearance = appearance }
                    }
                    .accessibilityIdentifier("appearance-\(appearance.rawValue)")
                }
            }
            if layout == .strip, let note = tool.note { stripNote(note) }
        }
    }

    // MARK: - Sfondo

    /// The papers, each drawn in the look's colour and grain.
    private var paper: some View {
        ToolRow(layout: layout) {
            ForEach(TodayPaper.allCases) { paper in
                ToolTile(title: Text(paper.title), chosen: look.paper == paper) {
                    withAnimation(.snappy) { look.paper = paper }
                } face: {
                    TodayBackgroundView(background: .plain, flavor: drawn.flavor, paper: paper, grain: drawn.grain,
                                        mode: drawn.appearance.flavorMode)
                        .environment(\.colorScheme, pageScheme)
                }
                .accessibilityIdentifier("paper-\(paper.rawValue)")
            }
        }
    }

    /// The patterns, each drawn over the look's paper.
    private var motif: some View {
        ToolRow(layout: layout) {
            ForEach(TodayBackground.allCases) { background in
                ToolTile(title: Text(background.title), chosen: look.background == background) {
                    withAnimation(.snappy) { look.background = background }
                } face: {
                    TodayBackgroundView(background: background, flavor: drawn.flavor, paper: drawn.paper,
                                        mode: drawn.appearance.flavorMode)
                        .environment(\.colorScheme, pageScheme)
                }
                .accessibilityIdentifier("motif-\(background.rawValue)")
            }
        }
    }

    /// The grain, from none to a hundred.
    private var grain: some View {
        ToolRuler(title: "Grana",
                  value: Binding { look.grain * 100 } set: { look.grain = $0 / 100 },
                  range: 0...100, step: 5)
            .accessibilityIdentifier("paper-grain")
    }

    /// The light the page is drawn in.
    private var pageScheme: ColorScheme {
        drawn.appearance.colorScheme ?? .light
    }

    // MARK: - Data

    /// The date's typefaces, each a "28" in it; then the rest of the text.
    private var typeface: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolRow(layout: layout) {
                ForEach(TodayStyle.DateFont.allCases) { font in
                    ToolTile(title: Text(font.title), chosen: look.dateFont == font) {
                        withAnimation(.snappy) { look.dateFont = font }
                    } face: {
                        Text(verbatim: "28")
                            .font(font.font(size: 24, weight: look.dateWeight))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.11))
                    }
                    .accessibilityIdentifier("date-font-\(font.rawValue)")
                }
            }
            ToolGroup(title: "Il resto del testo") {
                ChipRow(layout: layout) {
                    ForEach(TodayStyle.TextDesign.allCases) { design in
                        ToolChip(title: Text(design.title).fontDesign(design.design), chosen: look.textDesign == design) {
                            withAnimation(.snappy) { look.textDesign = design }
                        }
                    }
                }
            }
            .padding(.leading, layout == .strip ? 18 : 0)
        }
    }

    /// The date's size and weight, each on a ruler.
    private var dimensions: some View {
        VStack(spacing: 4) {
            ToolRuler(title: "Grandezza",
                      value: Binding { look.dateSize * 100 } set: { look.dateSize = $0 / 100 },
                      range: TodayStyle.dateSizes.lowerBound * 100...TodayStyle.dateSizes.upperBound * 100,
                      step: 5, unit: "%")
                .accessibilityIdentifier("date-size")
            ToolRuler(title: "Spessore",
                      value: Binding { 100 + look.dateWeight * 800 } set: { look.dateWeight = ($0 - 100) / 800 },
                      range: 100...900, step: 100)
                .accessibilityIdentifier("date-weight")
        }
    }

    /// The date in ink, or in the Flavor's colour.
    private var dateColour: some View {
        ChipRow(layout: layout) {
            ForEach(TodayStyle.DateColour.allCases) { colour in
                ToolChip(title: Text(colour.title),
                         dot: AnyShapeStyle(colour == .flavor ? drawn.accent(pageScheme) : (pageScheme == .dark ? Color.white : .black)),
                         chosen: look.dateColour == colour) {
                    withAnimation(.snappy) { look.dateColour = colour }
                }
                .accessibilityIdentifier("date-colour-\(colour.rawValue)")
            }
        }
    }

    /// How the date is laid out, and which side it sits on.
    private var dateShape: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChipRow(layout: layout) {
                ForEach(DateLayout.allCases) { dateLayout in
                    ToolChip(title: Text(dateLayout.title), chosen: look.dateLayout == dateLayout) {
                        withAnimation(.snappy) { look.dateLayout = dateLayout }
                    }
                }
            }
            ChipRow(layout: layout) {
                ForEach(DateAlignment.allCases) { alignment in
                    ToolChip(title: Text(Image(systemName: alignment.systemImage)), chosen: look.dateAlignment == alignment) {
                        withAnimation(.snappy) { look.dateAlignment = alignment }
                    }
                    .accessibilityLabel(Text(alignment.title))
                }
            }
        }
    }

    // MARK: - Saluto

    /// The date as the cards show it.
    private var cardDate: some View {
        Text(shell.day, format: .dateTime.day(.twoDigits).month(.twoDigits))
            .font(drawn.dateFont.font(size: 22, weight: drawn.dateWeight))
            .foregroundStyle(drawn.dateColour == .flavor ? AnyShapeStyle(drawn.accent(pageScheme)) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Every greeting drawn as the top of the page it makes, then none; the
    /// student's own words under them when they write their own.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToolRow(layout: layout, minimum: 96, spacing: 12) {
                ForEach(GreetingStyle.allCases) { style in
                    let chosen = look.showsGreeting && look.greeting == style
                    PageCard(look: look, title: Text(style.title), chosen: chosen) {
                        withAnimation(.snappy) {
                            look.showsGreeting = true
                            look.greeting = style
                        }
                        // The student's own words are written in their task: straight
                        // away when there are none yet, else on a second tap.
                        if style == .custom, let enterMode, chosen || look.customGreeting.isEmpty {
                            enterMode(.greeting)
                        }
                    } face: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(style.text(for: shell.day, firstName: session.student?.firstName, custom: look.customGreeting))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            cardDate
                        }
                    }
                    .accessibilityIdentifier("greeting-\(style.rawValue)")
                }
                if layout == .strip {
                    Rectangle().fill(Color(white: 0.23)).frame(width: 1, height: 96)
                }
                PageCard(look: look, title: Text("Nessun saluto"), chosen: !look.showsGreeting) {
                    withAnimation(.snappy) { look.showsGreeting = false }
                } face: {
                    VStack(alignment: .leading) {
                        Spacer(minLength: 0)
                        cardDate
                    }
                }
                .accessibilityIdentifier("greeting-none")
            }
            if enterMode == nil && look.showsGreeting && look.greeting == .custom {
                limitedField("Scrivi il tuo saluto", text: $look.customGreeting, limit: TodayStyle.customGreetingLimit)
                    .accessibilityIdentifier("greeting-field")
            }
        }
    }

    /// A text field with how much room is left.
    private func limitedField(_ prompt: LocalizedStringKey, text: Binding<String>, limit: Int) -> some View {
        HStack {
            TextField(prompt, text: text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($fieldFocused)
                .onChange(of: fieldFocused) { _, focused in typing.wrappedValue = focused }
            Text(verbatim: "\(text.wrappedValue.count)/\(limit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color(white: 0.11), in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, layout == .strip ? 18 : 0)
    }

    /// What sits beside the date, each drawn on the page; then the stickers,
    /// the words or the photos chosen.
    private var beside: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolRow(layout: layout, minimum: 96, spacing: 12) {
                ForEach(TodayAccessory.allCases) { accessory in
                    let chosen = look.accessory == accessory
                    PageCard(look: look, title: Text(accessory.title), chosen: chosen) {
                        withAnimation(.snappy) { look.accessory = accessory }
                        if let enterMode {
                            // Stickers and words have a task of their own: straight away
                            // when there is nothing yet, else on a second tap.
                            if accessory == .stickers && (chosen || look.stickers.isEmpty) { enterMode(.stickers) }
                            if accessory == .text && (chosen || look.accessoryText.isEmpty) { enterMode(.besideText) }
                        } else if accessory == .stickers && look.stickers.isEmpty {
                            pickStickers()
                        }
                    } face: {
                        besideFace(accessory)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("date-header-layout")

            switch look.accessory {
            case .none: EmptyView()
            case .stickers:
                if let enterMode {
                    taskButton("Modifica gli sticker", symbol: "hand.draw") { enterMode(.stickers) }
                        .accessibilityIdentifier("sticker-edit")
                } else {
                    stickerControls
                }
            case .text:
                if let enterMode {
                    taskButton("Modifica il testo", symbol: "character.cursor.ibeam") { enterMode(.besideText) }
                        .accessibilityIdentifier("accessory-text-edit")
                } else {
                    limitedField("Tutto pronto?", text: $look.accessoryText, limit: TodayStyle.accessoryTextLimit)
                        .accessibilityIdentifier("accessory-text")
                }
            case .photos: photoControls
            }
        }
    }

    /// A button that starts one of the iPhone's tasks.
    private func taskButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 18)
    }

    /// What a card of the beside tool shows: the date, and beside it the accessory.
    @ViewBuilder
    private func besideFace(_ accessory: TodayAccessory) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            cardDate
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .topTrailing) {
            switch accessory {
            case .none:
                EmptyView()
            case .stickers:
                let shown = Array(look.stickers.prefix(2))
                ZStack {
                    if shown.isEmpty {
                        Text(verbatim: "✨").font(.system(size: 22)).rotationEffect(.degrees(-10))
                        Text(verbatim: "📚").font(.system(size: 18)).offset(x: -18, y: 22).rotationEffect(.degrees(8))
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, sticker in
                            StickerContentView(content: sticker.content)
                                .frame(width: index == 0 ? 28 : 22, height: index == 0 ? 28 : 22)
                                .stickerOutline(look.stickerOutline)
                                .rotationEffect(.degrees(index == 0 ? -10 : 8))
                                .offset(x: index == 0 ? 0 : -18, y: index == 0 ? 0 : 22)
                        }
                    }
                }
            case .text:
                Text(look.accessoryText.isEmpty ? String(localized: "Tutto pronto?") : look.accessoryText)
                    .font(drawn.dateFont.font(size: 12, weight: max(drawn.dateWeight, 0.5)))
                    .foregroundStyle(drawn.accent(pageScheme))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(width: 46, alignment: .trailing)
                    .rotationEffect(.degrees(-4))
            case .photos:
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(drawn.accent(pageScheme))
            }
        }
    }

    /// The stickers on the page, to select or take away; a way to add more,
    /// the outline, and the selected one's actions.
    private var stickerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(look.stickers) { sticker in
                        let chosen = selectedSticker == sticker.id
                        Button {
                            selectedSticker = chosen ? nil : sticker.id
                        } label: {
                            StickerContentView(content: sticker.content)
                                .frame(width: 30, height: 30)
                                .frame(width: 44, height: 44)
                                .background(Color(white: 0.11), in: .rect(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    if chosen {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sticker.content.isEmoji ? Text("Emoji") : Text("Sticker"))
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                    Button(action: pickStickers) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.11), in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(look.stickers.count >= TodayStyle.maxStickers)
                    .accessibilityLabel(Text("Aggiungi sticker"))
                    .accessibilityIdentifier("sticker-controls-add")
                    Text("\(look.stickers.count) di \(TodayStyle.maxStickers)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, layout == .strip ? 18 : 0)
            }
            .scrollIndicators(.hidden)

            if let id = selectedSticker, look.stickers.contains(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    ForEach(StickerEdit.allCases, id: \.self) { edit in
                        Button {
                            withAnimation(.snappy) { selectedSticker = look.edit(sticker: id, edit) }
                        } label: {
                            Label(edit.title, systemImage: edit.systemImage)
                                .labelStyle(.iconOnly)
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.glass)
                        .tint(edit == .remove ? .red : .primary)
                        .disabled(edit == .duplicate && look.stickers.count >= TodayStyle.maxStickers)
                        .accessibilityIdentifier("sticker-\(edit)")
                    }
                }
                .padding(.horizontal, layout == .strip ? 18 : 0)
            }

            Toggle("Bordo bianco", isOn: $look.stickerOutline)
                .padding(.horizontal, layout == .strip ? 18 : 0)

            stripNote(selectedSticker == nil
                      ? "Trascinali sulla pagina; toccane uno per sceglierlo."
                      : "Trascinalo sulla pagina; la maniglia sull’angolo lo ingrandisce e lo ruota.")
        }
    }

    /// The photos stacked beside the date, and a way to choose them.
    private var photoControls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(look.photoIDs, id: \.self) { id in
                    StickerContentView(content: .image(id), fill: true)
                        .frame(width: 44, height: 44)
                        .clipShape(.rect(cornerRadius: 10))
                        .contextMenu {
                            Button("Rimuovi", systemImage: "trash", role: .destructive) {
                                withAnimation(.snappy) { look.removePhoto(id) }
                            }
                        }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: TodayStyle.maxPhotos, matching: .images) {
                    Label("Scegli le foto", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color(white: 0.11), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, layout == .strip ? 18 : 0)
        }
        .scrollIndicators(.hidden)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let resized = PlatformImage(data: data)?.resizedJPEG(maxSide: 900),
                       let id = try? StickerStore.shared.save(resized) {
                        withAnimation(.snappy) { look.addPhoto(id) }
                    }
                }
                photoItems = []
            }
        }
    }

    // MARK: - Schede

    /// What the cards are made of, each drawn on the page.
    private var surface: some View {
        ToolRow(layout: layout) {
            ForEach(TodayMaterial.allCases) { material in
                ToolTile(title: Text(material.title), chosen: look.material == material) {
                    withAnimation(.snappy) { look.material = material }
                } face: {
                    MaterialPreview(material: material, style: drawn)
                        .environment(\.colorScheme, pageScheme)
                }
                .accessibilityIdentifier("material-\(material.rawValue)")
            }
        }
    }

    /// Every kind of section in the page's order: a switch to show it, its
    /// settings a tap away, dragged to reorder. Then Oggi's bar buttons.
    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let enterMode {
                // On iPhone, what is on the page in order; the list is a task of its own.
                sectionsSummary
                Button("Modifica", systemImage: "list.bullet") { enterMode(.sections) }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("sections-edit")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sectionKinds.enumerated()), id: \.element) { index, kind in
                        sectionRow(kind)
                        if index < sectionKinds.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(Color(white: 0.11), in: .rect(cornerRadius: 14, style: .continuous))

                Text("Trascina ≡ per riordinare. Tocca una sezione per le sue opzioni.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Disponi sulla pagina", systemImage: "square.stack.3d.up") {
                withAnimation(.snappy) { arranging = true }
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("customize-editor-arrange")

            ToolGroup(title: "Barra di Oggi",
                      note: "Impostazioni e Personalizza restano sempre nella barra: sono la strada per tornarci.") {
                VStack(spacing: 0) {
                    Toggle("Profilo", isOn: $look.bar.showsProfile)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                    Divider().padding(.leading, 14)
                    Toggle("Giorno", isOn: $look.bar.showsDate)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                }
                .background(Color(white: 0.11), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, layout == .strip ? 18 : 0)
        .padding(.vertical, 4)
    }

    /// The sections on the page in order, each its symbol and name.
    private var sectionsSummary: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(look.visibleSections.enumerated()), id: \.element.id) { index, section in
                    HStack(spacing: 6) {
                        Text(verbatim: "\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: section.kind.systemImage)
                        Text(section.kind.title)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Color(white: 0.11), in: .capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Sulla pagina, in ordine"))
    }

    /// The kinds of section, those on the page first in their order, then the rest.
    private var sectionKinds: [TodaySection.Kind] {
        let listed = look.sections.map(\.kind)
        return listed + TodaySection.Kind.allCases.filter { !listed.contains($0) }
    }

    /// One section's row: its switch, what it is set to, and its settings when open.
    private func sectionRow(_ kind: TodaySection.Kind) -> some View {
        let section = look.section(kind)
        let shown = section.map { !$0.isHidden } ?? false
        let open = openSection == kind && shown
        let onlyOne = shown && look.visibleSections.count <= 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Button {
                    withAnimation(.snappy) { openSection = open ? nil : kind }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.systemImage)
                            .frame(width: 22)
                            .foregroundStyle(shown ? .primary : .tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .foregroundStyle(shown ? .primary : .secondary)
                            ((shown ? section?.summary : nil) ?? Text("Nascosta"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if shown {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(open ? 90 : 0))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!shown)
                Toggle(isOn: Binding {
                    shown
                } set: { on in
                    withAnimation(.snappy) {
                        if on { look.addSection(kind) } else { look.hideSection(kind) }
                    }
                }) {
                    Text(kind.title)
                }
                .labelsHidden()
                .disabled(onlyOne)
            }
            if open {
                SectionSettings(kind: kind, look: $look)
                    .padding(.leading, 32)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .draggable(kind.rawValue)
        .dropDestination(for: String.self) { dropped, _ in
            guard let raw = dropped.first, let moved = TodaySection.Kind(rawValue: raw), moved != kind else { return false }
            withAnimation(.snappy) { look.moveSection(moved, onto: kind) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("layout-section-\(kind.rawValue)")
        .accessibilityAction(named: "Sposta su") { withAnimation(.snappy) { look.moveSection(kind, by: -1) } }
        .accessibilityAction(named: "Sposta giù") { withAnimation(.snappy) { look.moveSection(kind, by: 1) } }
    }

    // MARK: - App

    /// The icon, and on iPhone how the Home Screen draws it.
    private var appIcon: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppIconPicker(look: $look, layout: layout == .strip ? .row : .grid(columns: 4))
            if layout == .strip {
                GlassSegmentedPicker("Aspetto della Home", selection: $homeLook) { Text($0.title) }
                    .accessibilityIdentifier("customize-home-look")
            }
        }
        .padding(.horizontal, layout == .strip ? 18 : 0)
        .padding(.vertical, 4)
    }
}

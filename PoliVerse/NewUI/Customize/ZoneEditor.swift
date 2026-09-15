import SwiftUI

/// The controls for one zone: a curated set and one fine control.
struct ZoneEditor: View {
    let zone: TodayLanding.Zone
    @Binding var style: TodayStyle
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    @State private var pickingStickers = false

    var body: some View {
        NavigationStack {
            Form {
                switch zone {
                case .bar: barControls
                case .date: dateControls
                case .greeting: greetingControls
                case .stickers: stickerControls
                case .section(let kind): sectionControls(kind)
                case .background: backgroundControls
                }
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            // Here, not on the sticker section: a sheet attached inside a Form
            // row does not present reliably.
            .sheet(isPresented: $pickingStickers) {
                StickerPicker(remaining: TodayStyle.maxStickers - style.stickers.count) { content in
                    style.addSticker(content)
                }
                .presentationDetents([.height(220)])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("customize-zone-done")
                }
            }
        }
    }

    // MARK: Theme

    /// The look's Flavor, material, text and background: everything behind
    /// and around the zones, together.
    @ViewBuilder
    private var backgroundControls: some View {
        Section {
            FlavorRow(flavor: $style.flavor)
        } header: {
            Text("Flavor")
        } footer: {
            Text("Un colore diventa sfondo, schede e il colore di pulsanti, schede selezionate e collegamenti in tutta l’app, sempre leggibili in chiaro e in scuro.")
        }
        Section("Materiale") {
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
        }
        Section("Testo") {
            Picker("Testo", selection: $style.textDesign) {
                ForEach(TodayStyle.TextDesign.allCases) { design in
                    Text(design.title).fontDesign(design.design).tag(design)
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Sfondo") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TodayBackground.allCases) { background in
                    Button { style.background = background } label: {
                        VStack(spacing: 6) {
                            TodayBackgroundView(background: background, flavor: style.flavor)
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
        }
    }

    // MARK: Bar

    @ViewBuilder
    private var barControls: some View {
        Section {
            Toggle("Profilo", isOn: $style.bar.showsProfile)
            Toggle("Impostazioni", isOn: $style.bar.showsSettings)
            Toggle("Giorno", isOn: $style.bar.showsDate)
            Toggle("Aggiungi", isOn: $style.bar.showsAdd)
        } header: {
            Text("Pulsanti")
        } footer: {
            Text("Il menu ••• resta sempre: è da lì che si torna in Personalizza.")
        }
    }

    // MARK: Stickers

    @ViewBuilder
    private var stickerControls: some View {
        Section {
            headerLayoutPicker
        }
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
            Button("Aggiungi sticker", systemImage: "plus") { pickingStickers = true }
                .disabled(style.stickers.count >= TodayStyle.maxStickers)
                .accessibilityIdentifier("sticker-controls-add")
        } header: {
            Text("Sticker")
        } footer: {
            Text("Tieni premuto sulla pagina per spostarli, ingrandirli e ruotarli.")
        }
    }

    /// Whether the top of the page is the date alone or the date beside
    /// stickers; offered with the date and with the stickers.
    private var headerLayoutPicker: some View {
        Picker("In alto", selection: $style.header) {
            Text("Solo data").tag(HeaderLayout.date)
            Text("Data e sticker").tag(HeaderLayout.dateAndStickers)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("date-header-layout")
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
        Section("Scheda") {
            Picker("Materiale", selection: section.material) {
                Text("Come la pagina").tag(TodayMaterial?.none)
                ForEach(TodayMaterial.allCases) { Text($0.title).tag(TodayMaterial?.some($0)) }
            }
            .accessibilityIdentifier("section-material")
            Picker("Densità", selection: section.density) {
                ForEach(TodaySection.Density.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Colore della data", isOn: section.tinted)
        }
        if kind.listsItems {
            Section {
                Stepper(value: section.itemLimit, in: TodaySection.itemLimits) {
                    Text("Elementi mostrati: \(section.wrappedValue.itemLimit)")
                }
            }
        }
        Section {
            Button("Togli dalla pagina", systemImage: "eye.slash", role: .destructive) {
                style.hideSection(kind)
                dismiss()
            }
        } footer: {
            Text("Tieni premuto sulla pagina per riordinare, aggiungere e togliere le sezioni. Una sezione tolta tiene le sue impostazioni.")
        }
    }

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

    @ViewBuilder
    private var dateLayoutControls: some View {
        Section("Disposizione") {
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
        Section {
            headerLayoutPicker
        } footer: {
            Text("Con gli sticker la data occupa metà della larghezza.")
        }
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
        Section {
            Picker("Colore", selection: $style.dateColour) {
                ForEach(TodayStyle.DateColour.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Colore")
        } footer: {
            Text("Il colore del Flavor si sceglie in Tema.")
        }
    }
}

/// The Flavor swatches, then the system's colour picker for any other colour.
private struct FlavorRow: View {
    @Binding var flavor: Flavor
    @Environment(\.self) private var environment

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Flavor.swatches) { swatch in
                    Button { flavor = swatch.flavor } label: {
                        Circle()
                            .fill(swatch.flavor.base.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if flavor == swatch.flavor {
                                    Circle().strokeBorder(.background, lineWidth: 3).padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(swatch.name))
                    .accessibilityIdentifier("flavor-\(swatch.flavor.hex)")
                    .accessibilityAddTraits(flavor == swatch.flavor ? .isSelected : [])
                }
                ColorPicker("Altro colore", selection: pickerColour, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("flavor-picker")
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// Any colour the picker returns, resolved to sRGB.
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
private struct MaterialPreview: View {
    let material: TodayMaterial
    let style: TodayStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TodayBackgroundView(background: style.background, flavor: style.flavor)
            .overlay {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(style.accent(scheme)).frame(width: 18, height: 4)
                    Capsule().fill(.primary.opacity(0.6)).frame(width: 26, height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(7)
                .todayMaterial(material, flavor: style.flavor, cornerRadius: 9)
                .padding(8)
            }
            .clipShape(.rect(cornerRadius: 14))
    }
}

extension TodayLanding.Zone {
    /// A few controls, fine in a sheet that leaves most of the page visible.
    var isShort: Bool {
        switch self {
        case .section: true
        case .bar, .greeting, .date, .stickers, .background: false
        }
    }
}

private extension PlacedSticker.Content {
    var isEmoji: Bool {
        if case .emoji = self { true } else { false }
    }
}

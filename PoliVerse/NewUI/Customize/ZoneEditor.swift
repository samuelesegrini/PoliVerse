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

    @ViewBuilder
    private var backgroundControls: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TodayBackground.allCases) { background in
                    Button { style.background = background } label: {
                        VStack(spacing: 6) {
                            TodayBackgroundView(background: background, tint: style.backgroundTint)
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
        Section {
            AccentRow(selection: $style.backgroundAccent, automatic: "Come la data")
        } header: {
            Text("Colore")
        } footer: {
            Text("Il motivo prende il colore della data, a meno di sceglierne uno.")
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
        Section {
            AccentRow(selection: $style.bar.tint, automatic: "App", followsDate: $style.bar.tintFollowsDate)
        } header: {
            Text("Colore dei controlli")
        } footer: {
            Text("Pulsanti, scheda selezionata e collegamenti in tutta l’app.")
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
            Picker("Scheda", selection: section.card) {
                ForEach(TodaySection.CardStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
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
                            .font(font.font(size: 28, weight: style.weight))
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
            HStack(spacing: 14) {
                ForEach(TodayStyle.Accent.allCases) { accent in
                    Button { style.dateAccent = accent } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if style.dateAccent == accent {
                                    Circle().strokeBorder(.background, lineWidth: 3).padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style.dateAccent == accent ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A row of colour swatches, after a first choice that keeps the default and,
/// where offered, one that follows the date.
private struct AccentRow: View {
    @Binding var selection: TodayStyle.Accent?
    let automatic: LocalizedStringKey
    var followsDate: Binding<Bool>?

    private var following: Bool { followsDate?.wrappedValue ?? false }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                chip(automatic, selected: selection == nil && !following) {
                    selection = nil
                    followsDate?.wrappedValue = false
                }
                if let followsDate {
                    chip("Come la data", selected: following) { followsDate.wrappedValue = true }
                        .accessibilityIdentifier("accent-date")
                }
                ForEach(TodayStyle.Accent.allCases) { accent in
                    Button {
                        selection = accent
                        followsDate?.wrappedValue = false
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selection == accent && !following {
                                    Circle().strokeBorder(.background, lineWidth: 3).padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accent.title))
                    .accessibilityIdentifier("accent-\(accent.rawValue)")
                    .accessibilityAddTraits(selection == accent && !following ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.quaternary.opacity(0.6), in: .capsule)
                .overlay {
                    if selected { Capsule().strokeBorder(.tint, lineWidth: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

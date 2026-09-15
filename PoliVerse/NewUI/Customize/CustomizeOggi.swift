import SwiftUI

/// Personalizza, opened from Oggi's ••• menu. It opens as a gallery of saved
/// looks, paged like the Lock Screen's: swipe between them at a reduced size,
/// Personalizza to edit the one in the middle, + to add a new one, Fine to use
/// it. Editing shows the page at full size with its zones outlined; nothing is
/// kept until Fine.
struct CustomizeOggi: View {
    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var active = TodayStyle()
    @AppStorage(TodayStyle.libraryKey) private var storedLibrary = ""
    @AppStorage(TodayStyle.selectionKey) private var storedSelection = 0

    @State private var looks: [TodayStyle] = []
    @State private var page: Int?
    @State private var editingIndex: Int?
    @State private var draft = TodayStyle()
    @State private var editingZone: TodayLanding.Zone?

    var body: some View {
        ZStack {
            if let index = editingIndex {
                editor(index)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else {
                gallery
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: editingIndex)
        .onAppear(perform: load)
    }

    // MARK: - Gallery

    /// How much the app shrinks into the middle card.
    static let cardScale: CGFloat = 0.72

    private var gallery: some View {
        GeometryReader { proxy in
            let screen = CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            let cardSize = CGSize(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)

            ZStack {
                // Cards the size of the shrunk app, centred on the screen as
                // the shrunk app is, so the swap between them does not move.
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 18) {
                        ForEach(Array(looks.enumerated()), id: \.offset) { index, look in
                            card(look, screen: screen)
                                .frame(width: cardSize.width, height: cardSize.height)
                                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                    view
                                        .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                        .opacity(phase.isIdentity ? 1 : 0.6)
                                }
                                .id(index)
                                .onTapGesture { beginEditing(index) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page, anchor: .center)
                .contentMargins(.horizontal, (screen.width - cardSize.width) / 2, for: .scrollContent)
                .frame(width: screen.width, height: screen.height)

                VStack {
                    HStack {
                        Button("Annulla", role: .cancel) { close() }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Usa", systemImage: "checkmark") {
                            use(page ?? 0)
                            close()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 20)
                    // The gallery ignores the safe area to match the shrunk
                    // app, so the status bar and home indicator are cleared by hand.
                    .padding(.top, 60)

                    Spacer()

                    VStack(spacing: 14) {
                        HStack(spacing: 7) {
                            ForEach(looks.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == (page ?? 0) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .animation(.snappy, value: page)

                        HStack(spacing: 12) {
                            Button { beginEditing(page ?? 0) } label: {
                                Label("Personalizza", systemImage: "paintbrush")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.glass)

                            Button("Nuovo aspetto", systemImage: "plus", action: addLook)
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .frame(width: 50, height: 50)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                        }
                        .padding(.horizontal, 60)
                    }
                    .padding(.bottom, 40)
                }
            }
            .frame(width: screen.width, height: screen.height)
        }
        .ignoresSafeArea()
        .background(Color(.secondarySystemBackground))
    }

    /// A look drawn as the app would be at full screen size, with a quiet copy
    /// of the navigation bar, then scaled into a card.
    private func card(_ look: TodayStyle, screen: CGSize) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 62)
            BarSilhouette(day: shell.day)
                .padding(.horizontal, 16)
            TodayLanding(day: shell.day, style: look)
            Spacer(minLength: 0)
        }
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 48))
        .scaleEffect(Self.cardScale)
        .frame(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        .shadow(color: .black.opacity(0.18), radius: 24 * Self.cardScale, y: 10 * Self.cardScale)
        .allowsHitTesting(false)
        .contentShape(.rect(cornerRadius: 48 * Self.cardScale))
    }

    // MARK: - Editor

    private func editor(_ index: Int) -> some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, style: draft, editing: true) { editingZone = $0 }
                    .padding(.top, 8)
                    .padding(.bottom, 360)
            }
            .background(.background)
            .navigationTitle("Personalizza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", role: .cancel) { editingIndex = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") {
                        looks[index] = draft
                        persist()
                        editingIndex = nil
                    }
                }
            }
            .sheet(item: $editingZone) { zone in
                ZoneEditor(zone: zone, style: $draft)
                    .presentationDetents([.height(320), .medium])
                    // The page stays live behind the editor, as on the Lock Screen.
                    .presentationBackgroundInteraction(.enabled)
            }
        }
    }

    // MARK: - Actions

    private func load() {
        looks = TodayStyle.library(from: storedLibrary, active: active)
        page = min(storedSelection, looks.count - 1)
    }

    private func beginEditing(_ index: Int) {
        guard looks.indices.contains(index) else { return }
        draft = looks[index]
        editingIndex = index
    }

    private func addLook() {
        looks.append(TodayStyle())
        persist()
        withAnimation(.snappy) { page = looks.count - 1 }
        beginEditing(looks.count - 1)
    }

    private func use(_ index: Int) {
        guard looks.indices.contains(index) else { return }
        storedSelection = index
        active = looks[index]
        persist()
    }

    private func persist() {
        storedLibrary = TodayStyle.encodeLibrary(looks)
    }

    private func close() {
        shell.isCustomizing = false
    }
}

/// Oggi's navigation bar as shapes, for the gallery cards.
private struct BarSilhouette: View {
    let day: Date
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.quaternary).frame(width: 44, height: 44)
            Circle().fill(.quaternary).frame(width: 44, height: 44)
            Spacer()
            Text(day.formatted(.dateTime.day().month(.abbreviated).locale(locale)).capitalized)
                .font(.headline)
            Spacer()
            Capsule().fill(.quaternary).frame(width: 100, height: 44)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

/// The controls for one zone: a curated set and one fine control.
private struct ZoneEditor: View {
    let zone: TodayLanding.Zone
    @Binding var style: TodayStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch zone {
                case .date: dateControls
                case .greeting: Toggle("Mostra il saluto", isOn: $style.showsGreeting)
                case .upcoming: Toggle("Mostra In arrivo", isOn: $style.showsUpcoming)
                case .timetable: Toggle("Mostra l’orario", isOn: $style.showsTimetable)
                }
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var dateControls: some View {
        Section("Carattere") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
                }
            }
            Slider(value: $style.dateWeight, in: 0...1) {
                Text("Spessore")
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "bold")
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

#Preview("Personalizza") {
    CustomizeOggi().previewEnvironment()
}

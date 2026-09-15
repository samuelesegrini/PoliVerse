import SwiftUI

/// Personalizza, opened from Oggi's ••• menu. It opens as a gallery of saved
/// looks, paged like the Lock Screen's: swipe between them at a reduced size,
/// Personalizza to edit the one in the middle, + to add a new one, Fine to use
/// it. Editing shows the page at full size with its zones outlined; nothing is
/// kept until Fine.
///
/// Laid over the app by ``NewRootView``. Like the Lock Screen, the look in use
/// starts covering the screen, exactly where the app is, and shrinks into the
/// middle card while the rest of the gallery fades in; closing grows the
/// middle card back over the app before the gallery goes.
struct CustomizeOggi: View {
    @Environment(\.shell) private var shell
    @Environment(Session.self) private var session
    @Environment(AgendaService.self) private var agenda
    @AppStorage(TodayStyle.storageKey) private var active = TodayStyle()
    @AppStorage(TodayStyle.libraryKey) private var storedLibrary = ""
    @AppStorage(TodayStyle.selectionKey) private var storedSelection = 0

    @State private var looks: [TodayStyle]
    @State private var page: Int?
    /// The middle card covers the screen: on opening, and on closing.
    @State private var expanded = true
    @State private var editing: EditedLook?
    /// A look added with + that has not been saved yet.
    @State private var unsavedLook: Int?
    @Namespace private var cards

    /// The look open in the editor. Presented as an item, so the editor keeps
    /// its content while it zooms back into the card.
    private struct EditedLook: Identifiable {
        let index: Int
        let look: TodayStyle
        var id: Int { index }
    }

    /// How much smaller than the screen a card is.
    static let cardScale: CGFloat = 0.68
    private static let expand = Animation.spring(duration: 0.45, bounce: 0.1)

    init() {
        // Read before the first layout, so the carousel starts on the look in
        // use instead of scrolling to it while it shrinks.
        let defaults = UserDefaults.standard
        let looks = TodayStyle.library(from: defaults.string(forKey: TodayStyle.libraryKey) ?? "", active: TodayStyle())
        _looks = State(initialValue: looks)
        _page = State(initialValue: min(defaults.integer(forKey: TodayStyle.selectionKey), looks.count - 1))
    }

    var body: some View {
        GeometryReader { proxy in
            // The cards stand for the whole screen, status bar and home
            // indicator included, so they are measured without the safe area.
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            ZStack {
                Color(.secondarySystemBackground)
                    .opacity(expanded ? 0 : 1)
                Group {
                    carousel(screen: screen, insets: insets)
                    controls
                        .padding(.top, insets.top)
                        .padding(.bottom, insets.bottom)
                        .opacity(expanded ? 0 : 1)
                }
                .allowsHitTesting(!expanded)
            }
            .frame(width: screen.width, height: screen.height)
            // Takes every touch while it is up, growing back included, so none
            // reaches the app underneath.
            .contentShape(.rect)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(Self.expand) { expanded = false }
        }
        // The editor zooms out of the card being edited and back into it.
        .fullScreenCover(item: $editing, onDismiss: dropCancelledLook) { edited in
            LookEditor(look: edited.look) { saved in
                save(saved, at: edited.index)
            }
            .navigationTransition(.zoom(sourceID: edited.index, in: cards))
        }
    }

    // MARK: - Gallery

    private func carousel(screen: CGSize, insets: EdgeInsets) -> some View {
        let cardSize = CGSize(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 18) {
                ForEach(Array(looks.enumerated()), id: \.offset) { index, look in
                    let middle = index == (page ?? 0)
                    card(look, screen: screen, insets: insets)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .scrollTransition(.interactive, axis: .horizontal) { [expanded] view, phase in
                            // Off while covering the screen, where it would let
                            // the app show through.
                            view
                                .scaleEffect(phase.isIdentity || expanded ? 1 : 0.92)
                                .opacity(phase.isIdentity || expanded ? 1 : 0.6)
                        }
                        .matchedTransitionSource(id: index, in: cards)
                        .modifier(FillScreen(progress: middle && expanded ? 1 : 0, screen: screen))
                        .opacity(middle || !expanded ? 1 : 0)
                        .zIndex(middle ? 1 : 0)
                        .id(index)
                        .onTapGesture { select(index) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Aspetto \(index + 1)"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("customize-card-\(index)")
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $page, anchor: .center)
        .scrollDisabled(expanded)
        .contentMargins(.horizontal, (screen.width - cardSize.width) / 2, for: .scrollContent)
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Annulla", role: .cancel) { close() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("customize-cancel")
                Spacer()
                Button("Usa", systemImage: "checkmark") {
                    use(page ?? 0)
                    close()
                }
                .accessibilityIdentifier("customize-use")
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

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
                        .accessibilityIdentifier("customize-add")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 50, height: 50)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
                .padding(.horizontal, 60)
            }
            .padding(.bottom, 4)
        }
    }

    /// A look drawn as the app is at full screen size, bars included, then
    /// scaled into a card.
    private func card(_ look: TodayStyle, screen: CGSize, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            // The system's inline bar is 54 points tall; its controls sit in
            // the top 44.
            ReplicaNavigationBar(student: session.student, day: shell.day)
                .padding(.bottom, 10)
            TodayLanding(day: shell.day, style: look)
            Spacer(minLength: 0)
        }
        .padding(.top, insets.top)
        .overlay(alignment: .bottom) {
            if !shell.singlePage {
                VStack(spacing: 8) {
                    if let current = CurrentClass.forAccessory(from: agenda.events, now: .now) {
                        ReplicaAccessory(current: current)
                    }
                    ReplicaTabBar()
                }
                // Where the system floats the tab bar: lower than the safe
                // area, above the home indicator.
                .padding(.bottom, max(insets.bottom - 13, 0))
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .background(TodayBackgroundView(background: look.background, tint: look.backgroundTint))
        .clipShape(.rect(cornerRadius: 48))
        .scaleEffect(Self.cardScale)
        .frame(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        .shadow(color: .black.opacity(0.18), radius: 24 * Self.cardScale, y: 10 * Self.cardScale)
        .allowsHitTesting(false)
        .contentShape(.rect(cornerRadius: 48 * Self.cardScale))
    }

    // MARK: - Actions

    /// The middle card opens its editor; a card to the side comes to the middle.
    private func select(_ index: Int) {
        if index == page {
            beginEditing(index)
        } else {
            withAnimation(.snappy) { page = index }
        }
    }

    private func beginEditing(_ index: Int) {
        guard looks.indices.contains(index) else { return }
        editing = EditedLook(index: index, look: looks[index])
    }

    /// Adds a blank look at the end, brings it to the middle, and opens it
    /// once it is there, so the editor zooms out of its card.
    private func addLook() {
        looks.append(TodayStyle())
        let index = looks.count - 1
        unsavedLook = index
        withAnimation(.snappy) { page = index } completion: {
            beginEditing(index)
        }
    }

    /// Editing a look is choosing it, as on the Lock Screen.
    private func save(_ look: TodayStyle, at index: Int) {
        guard looks.indices.contains(index) else { return }
        looks[index] = look
        unsavedLook = nil
        use(index)
        page = index
        editing = nil
    }

    /// A look added with + and then cancelled goes, once the editor has
    /// zoomed back into its card.
    private func dropCancelledLook() {
        guard let index = unsavedLook else { return }
        unsavedLook = nil
        withAnimation(.snappy) {
            page = min(storedSelection, index - 1)
        } completion: {
            looks.remove(at: index)
        }
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

    /// Grows the middle card back over the app, then goes. Cancelled, the
    /// carousel first returns to the look in use, which is what the app shows.
    private func close() {
        withAnimation(Self.expand) {
            page = min(storedSelection, looks.count - 1)
            expanded = true
        } completion: {
            shell.isCustomizing = false
        }
    }
}

/// One look at full size with its zones outlined. Tapping a zone opens its
/// controls; nothing reaches the look until Fine.
private struct LookEditor: View {
    let onSave: (TodayStyle) -> Void

    @Environment(\.shell) private var shell
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodayStyle
    @State private var editingZone: TodayLanding.Zone?

    init(look: TodayStyle, onSave: @escaping (TodayStyle) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: look)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, style: draft, editing: true) { editingZone = $0 }
                    .padding(.top, 8)
                    .padding(.bottom, 360)
            }
            // The look's own ground, as on the card it zooms out of.
            .background(TodayBackgroundView(background: draft.background, tint: draft.backgroundTint).ignoresSafeArea())
            .navigationTitle("Personalizza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("customize-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { onSave(draft) }
                        .accessibilityIdentifier("customize-editor-done")
                }
                // The background is behind every zone, so it has its own
                // button, where the Lock Screen keeps its wallpaper.
                ToolbarItem(placement: .bottomBar) {
                    Button { editingZone = .background } label: {
                        Label("Sfondo", systemImage: "square.grid.3x3.square")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("customize-editor-background")
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
}

/// Scales a card about its centre until it covers the screen. A transform, not
/// a new frame: the card's content keeps its layout all the way.
private struct FillScreen: GeometryEffect {
    /// 0 at card size, 1 covering the screen.
    var progress: CGFloat
    let screen: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard size.width > 0, size.height > 0 else { return ProjectionTransform() }
        let full = max(screen.width / size.width, screen.height / size.height)
        let scale = 1 + (full - 1) * progress
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return ProjectionTransform(CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y))
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
                case .background: backgroundControls
                }
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("customize-zone-done")
                }
            }
        }
    }

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
        } footer: {
            Text("Il motivo prende il colore della data.")
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

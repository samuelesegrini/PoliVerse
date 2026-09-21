import SwiftUI

/// Personalizza, opened from Oggi's bar: one surface with two modes.
///
/// **Sfoglia.** The saved looks are paged like the Lock Screen's, at a reduced
/// size. The look in the middle is the look the app uses — swiping is
/// choosing, and the page behind changes with it. There is nothing to confirm,
/// and nothing to lose: every look stays saved, so swiping back undoes it.
///
/// **Modifica.** Tapping the middle card grows it to full size in place and
/// raises the bento panel. Changes land on the look as they are made, exactly
/// as the app will draw them, and ``Ripristina`` puts the look back the way it
/// was when editing started. Fine lowers the panel and shrinks the card back.
///
/// So the whole flow has two ways out, each meaning one thing: Fine leaves
/// editing, Chiudi leaves Personalizza. Nothing else commits anything.
///
/// Laid over the app by ``RootView``. Like the Lock Screen, the look in use
/// starts covering the screen, exactly where the app is, and shrinks into the
/// middle card while the rest of the gallery fades in; closing grows the
/// middle card back over the app before the gallery goes.
struct CustomizeOggi: View {
    @Environment(\.shell) private var shell
    @Environment(Session.self) private var session
    @Environment(AgendaModel.self) private var agenda
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var active = TodayStyle()
    @AppStorage(TodayStyle.libraryKey) private var storedLibrary = ""
    @AppStorage(TodayStyle.selectionKey) private var storedSelection = 0

    @State private var library: LookLibrary
    @State private var page: Int?
    /// The card whose deletion is being confirmed.
    @State private var deleting: Int?
    /// The middle card covers the screen: on opening, while editing, and on
    /// closing.
    @State private var expanded = true
    /// The middle card is being edited rather than browsed.
    @State private var editing = false
    /// The look as it was when editing started, for Ripristina.
    @State private var restorePoint: TodayStyle?
    @State private var panelPath: [CustomizePage] = []
    @State private var panelDetent = BentoPanel.small
    @State private var arranging = false
    /// Where a new look comes from: a copy, a theme, or nothing.
    @State private var addingLook = false
    /// The card being renamed.
    @State private var renaming: Int?
    @State private var newName = ""

    /// How much smaller than the screen a card is.
    static let cardScale: CGFloat = 0.68
    private static let expand = Animation.spring(duration: 0.45, bounce: 0.1)

    init() {
        // Read before the first layout, so the carousel starts on the look in
        // use instead of scrolling to it while it shrinks.
        let defaults = UserDefaults.standard
        let looks = TodayStyle.library(from: defaults.string(forKey: TodayStyle.libraryKey) ?? "", active: TodayStyle())
        let library = LookLibrary(looks: looks, selection: defaults.integer(forKey: TodayStyle.selectionKey))
        _library = State(initialValue: library)
        _page = State(initialValue: library.selection)
    }

    /// The look in the middle: the one the app is using, and the one the panel
    /// edits. Writing to it saves at once — there is no draft.
    private var middleLook: Binding<TodayStyle> {
        Binding {
            let index = page ?? library.selection
            return library.looks.indices.contains(index) ? library.looks[index] : library.active
        } set: { look in
            let index = page ?? library.selection
            guard library.looks.indices.contains(index) else { return }
            library.save(look, at: index)
            if index == library.selection { active = library.active }
        }
    }

    private var middle: Int { page ?? library.selection }

    /// Editing has changed the look since it started.
    private var hasChanges: Bool {
        guard let restorePoint, library.looks.indices.contains(middle) else { return false }
        return library.looks[middle] != restorePoint
    }

    /// Full size: covering the screen on the way in and out, and while editing.
    private var filled: Bool { expanded || editing }

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
                carousel(screen: screen, insets: insets)
                controls(insets: insets)
                    .opacity(expanded ? 0 : 1)
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
        // The panel belongs to editing: it rises with it and steps away while
        // sections are being arranged.
        .sheet(isPresented: Binding(get: { editing && !arranging }, set: { _ in })) {
            BentoPanel(style: middleLook, path: $panelPath, arranging: $arranging, detent: $panelDetent)
                .presentationDetents([BentoPanel.small, .large], selection: $panelDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: BentoPanel.small))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $addingLook) {
            NewLookSheet(copying: library.looks.indices.contains(middle) ? library.looks[middle] : library.active,
                         add: add)
                .presentationDetents([.large])
        }
        .confirmationDialog("Eliminare questo stile?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina stile", role: .destructive) {
                if let deleting { delete(deleting) }
            }
            .accessibilityIdentifier("customize-delete-confirm")
        } message: {
            Text("Non si può annullare.")
        }
        .alert("Nome dello stile", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Stile", text: $newName)
                .accessibilityIdentifier("customize-name-field")
            Button("Annulla", role: .cancel) {}
            Button("Salva") {
                if let renaming {
                    library.rename(newName.trimmingCharacters(in: .whitespaces), at: renaming)
                    if renaming == library.selection { active = library.active }
                    persist()
                }
            }
        }
    }

    // MARK: - Gallery

    private func carousel(screen: CGSize, insets: EdgeInsets) -> some View {
        let cardSize = CGSize(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        return ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(library.looks.enumerated()), id: \.offset) { index, look in
                        let isMiddle = index == middle
                        slot(look, at: index, screen: screen, insets: insets)
                            .frame(width: cardSize.width, height: cardSize.height)
                            .scrollTransition(.interactive, axis: .horizontal) { [filled] view, phase in
                                // Off while covering the screen, where it would let
                                // the app show through.
                                view
                                    .scaleEffect(phase.isIdentity || filled ? 1 : 0.92)
                                    .opacity(phase.isIdentity || filled ? 1 : 0.6)
                            }
                            .modifier(FillScreen(progress: isMiddle && filled ? 1 : 0, screen: screen))
                            .opacity(isMiddle || !filled ? 1 : 0)
                            .zIndex(isMiddle ? 1 : 0)
                            .id(index)
                            .accessibilityIdentifier("customize-card-\(index)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page, anchor: .center)
            .scrollDisabled(filled)
            .contentMargins(.horizontal, (screen.width - cardSize.width) / 2, for: .scrollContent)
            // The position's first value is not applied to a lazy stack: without
            // this the carousel opened on the first look while the look in use,
            // off to the side, was the one shrinking out of the app.
            .onAppear { reader.scrollTo(page, anchor: .center) }
            // Swiping is choosing: the app takes the look that comes to rest in
            // the middle. Every look stays saved, so swiping back undoes it.
            .onChange(of: page) { _, page in
                guard !editing, let page else { return }
                use(page)
            }
        }
    }

    /// One place in the carousel: a card to browse, or the live page to edit.
    @ViewBuilder
    private func slot(_ look: TodayStyle, at index: Int, screen: CGSize, insets: EdgeInsets) -> some View {
        if editing, index == middle {
            editorPage(screen: screen, insets: insets)
        } else {
            card(look, screen: screen, insets: insets)
                .onTapGesture { select(index) }
                .contextMenu { cardMenu(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(look.displayName(at: index)))
                .accessibilityValue(index == library.selection ? Text("In uso") : Text("\(index + 1) di \(library.looks.count)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Tocca per personalizzare"))
                .accessibilityActions { cardMenu(index) }
        }
    }

    @ViewBuilder
    private func cardMenu(_ index: Int) -> some View {
        Button("Rinomina", systemImage: "pencil") {
            newName = library.looks.indices.contains(index) ? library.looks[index].name : ""
            renaming = index
        }
        .accessibilityIdentifier("customize-rename")
        Button("Duplica", systemImage: "plus.square.on.square") {
            guard library.looks.indices.contains(index) else { return }
            add(copy(of: library.looks[index]))
        }
        .accessibilityIdentifier("customize-duplicate")
        if library.canRemove {
            Button("Elimina stile", systemImage: "trash", role: .destructive) { deleting = index }
        }
    }

    // MARK: - Controls

    private func controls(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, insets.top + 4)

            Spacer()

            if !editing {
                browseControls
                    .padding(.bottom, insets.bottom + 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: editing)
    }

    @ViewBuilder
    private var topBar: some View {
        if editing {
            // While arranging, the only way on is Fine, back to editing: the
            // page underneath is the thing being dragged.
            HStack {
                if hasChanges, !arranging {
                    Button("Ripristina", systemImage: "arrow.uturn.backward") { restore() }
                        .labelStyle(.titleOnly)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("customize-restore")
                }
                Spacer()
                Text(arranging ? "Disponi" : middleLook.wrappedValue.displayName(at: middle))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Fine", systemImage: "checkmark") {
                    if arranging {
                        withAnimation(.snappy) { arranging = false }
                    } else {
                        endEditing()
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier(arranging ? "customize-arrange-done" : "customize-edit-done")
            }
        } else {
            HStack {
                // Every look is saved and the one in the middle is already in
                // use: Chiudi has nothing left to decide.
                Button("Chiudi", role: .close) { close() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("customize-cancel")
                Spacer()
            }
        }
    }

    private var browseControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(library.looks.indices, id: \.self) { index in
                    Circle()
                        .fill(index == middle ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Stile \(middle + 1) di \(library.looks.count)"))

            HStack(spacing: 12) {
                Button { beginEditing() } label: {
                    Label("Personalizza", systemImage: "paintbrush")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("customize-edit")

                // The same 44-point label as Personalizza inside the same
                // glass style, so the two come out the same height. A frame
                // on the button itself sized only the hit area: the glass
                // is drawn around the label, and was left a small circle.
                Button { addingLook = true } label: {
                    Label("Nuovo stile", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        // Larger than the brush beside it: alone in its
                        // circle, a body-size plus reads as too light.
                        // Sized inside the fixed frame, so the button keeps
                        // Personalizza's height.
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("customize-add")
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 60)
        }
    }

    // MARK: - The page

    /// A look drawn as the app is at full screen size, bars included, then
    /// scaled into a card.
    private func card(_ look: TodayStyle, screen: CGSize, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            // The system's inline bar is 54 points tall; its controls sit in
            // the top 44.
            ReplicaNavigationBar(student: session.student, day: shell.day, bar: look.bar)
                .padding(.bottom, 10)
            TodayLanding(day: shell.day, style: look)
            Spacer(minLength: 0)
        }
        .padding(.top, insets.top)
        .overlay(alignment: .bottom) {
            if !shell.singlePage {
                VStack(spacing: 8) {
                    if look.wantsCurrentClassAccessory, let current = CurrentClass.forAccessory(from: agenda.events, now: .now) {
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
        .tint(look.controlTint(scheme))
        .background(TodayBackgroundView(style: look))
        .clipShape(.rect(cornerRadius: 48))
        .scaleEffect(Self.cardScale)
        .frame(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        .shadow(color: .black.opacity(0.18), radius: 24 * Self.cardScale, y: 10 * Self.cardScale)
        .allowsHitTesting(false)
        .contentShape(.rect(cornerRadius: 48 * Self.cardScale))
    }

    /// The same page, live: zones outlined and each one a way into its
    /// controls. It stands in the carousel where its card was, so growing into
    /// it and back is one movement rather than a screen arriving.
    private func editorPage(screen: CGSize, insets: EdgeInsets) -> some View {
        ScrollView {
            TodayLanding(day: shell.day, draft: middleLook, arranging: arranging,
                         onAddSticker: { panelPath = [.accessory] }) { zone in
                // Holding a zone arranges the page; the tap that ends the
                // hold must not also open the zone.
                guard !arranging else { return }
                panelPath = [CustomizePage(zone: zone)]
                panelDetent = BentoPanel.small
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 52)
            .padding(.bottom, arranging ? 120 : 420)
        }
        .frame(width: screen.width, height: screen.height)
        .background(TodayBackgroundView(style: middleLook.wrappedValue))
        .scaleEffect(Self.cardScale)
        .frame(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        .sensoryFeedback(.impact(weight: .medium), trigger: arranging) { _, new in new }
        .tint(middleLook.wrappedValue.controlTint(scheme))
        // The look's own light on the page alone: as `preferredColorScheme`
        // this flipped the controls over it too, and a dark look being edited
        // in daylight took the buttons with it.
        .environment(\.colorScheme, middleLook.wrappedValue.appearance.colorScheme ?? scheme)
    }

    // MARK: - Actions

    /// The middle card opens for editing; a card to the side comes to the
    /// middle, which is also what puts it in use.
    private func select(_ index: Int) {
        if index == middle {
            beginEditing()
        } else {
            withAnimation(.snappy) { page = index }
        }
    }

    private func beginEditing() {
        guard library.looks.indices.contains(middle) else { return }
        restorePoint = library.looks[middle]
        panelPath = []
        panelDetent = BentoPanel.small
        withAnimation(Self.expand) { editing = true }
    }

    private func endEditing() {
        arranging = false
        panelPath = []
        restorePoint = nil
        withAnimation(Self.expand) { editing = false }
        persist()
    }

    /// Puts the look back the way it was when editing started. The one step
    /// back the live model needs: everything else is visible and reversible by
    /// changing it again.
    private func restore() {
        guard let restorePoint else { return }
        withAnimation(.snappy) { middleLook.wrappedValue = restorePoint }
    }

    /// A copy carries the look's name with a mark, so two cards are never the
    /// same word.
    private func copy(of look: TodayStyle) -> TodayStyle {
        var copy = look
        copy.name = look.name.isEmpty ? "" : String("\(look.name) 2".prefix(TodayStyle.nameLimit))
        return copy
    }

    /// Adds a look beside the one in the middle, brings it there — which puts
    /// it in use — and opens it for editing.
    private func add(_ look: TodayStyle) {
        addingLook = false
        let index = library.insert(look, after: middle)
        persist()
        withAnimation(.snappy) { page = index } completion: {
            use(index)
            beginEditing()
        }
    }

    private func use(_ index: Int) {
        guard index != library.selection, library.looks.indices.contains(index) else { return }
        library.use(index)
        active = library.active
        storedSelection = library.selection
    }

    /// Deleting the look in use hands the page to its neighbour.
    private func delete(_ index: Int) {
        guard library.remove(at: index) else { return }
        active = library.active
        // The cards are keyed by position: the one in the middle stays there
        // only if the page moves back with it.
        withAnimation(.snappy) { page = min(index < middle ? middle - 1 : middle, library.looks.count - 1) }
        persist()
    }

    private func persist() {
        storedLibrary = TodayStyle.encodeLibrary(library.looks)
        storedSelection = library.selection
        // Sticker images no saved style draws any more.
        let inUse = library.looks.reduce(into: active.storedImageIDs) { $0.formUnion($1.storedImageIDs) }
        StickerStore.shared.prune(keeping: inUse)
    }

    /// Grows the middle card back over the app, then goes. The app is already
    /// wearing the middle look, so there is nothing to settle first.
    private func close() {
        persist()
        withAnimation(Self.expand) {
            expanded = true
        } completion: {
            shell.isCustomizing = false
        }
    }
}

/// Where a new look comes from. A blank page is the rarest thing a student
/// wants and the only thing + used to offer; a copy of what they are looking
/// at is the commonest.
private struct NewLookSheet: View {
    let copying: TodayStyle
    let add: (TodayStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button { add(copying) } label: {
                        HStack(spacing: 14) {
                            swatch(copying)
                                .frame(width: 64, height: 86)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Copia questo stile")
                                    .font(.headline)
                                Text("Parti da com'è adesso e cambia quello che vuoi.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-new-duplicate")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temi")
                            .font(.headline)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(TodayStyle.presets.enumerated()), id: \.offset) { index, preset in
                                Button { add(preset) } label: {
                                    VStack(spacing: 6) {
                                        swatch(preset)
                                            .frame(height: 132)
                                        Text(preset.displayName(at: index))
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("customize-new-preset-\(index)")
                            }
                        }
                    }

                    Button("Pagina vuota", systemImage: "square.dashed") { add(TodayStyle()) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("customize-new-blank")
                }
                .padding(20)
            }
            .navigationTitle("Nuovo stile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", role: .cancel) { dismiss() }
                }
            }
        }
    }

    /// A look small enough to choose by: its background, its colour and the
    /// shape of its date. Not the whole page — at this size the page is noise.
    private func swatch(_ look: TodayStyle) -> some View {
        TodayBackgroundView(style: look)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("21")
                        .font(look.dateFont.font(size: 30, weight: look.dateWeight))
                        .foregroundStyle(look.dateTint(scheme))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(look.accent(scheme).opacity(0.3))
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(look.accent(scheme).opacity(0.18))
                        .frame(height: 18)
                }
                .padding(10)
            }
            .environment(\.colorScheme, look.appearance.colorScheme ?? scheme)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}

extension BentoPanel {
    /// The panel's resting height: the page above stays visible and live.
    static let small = PresentationDetent.fraction(0.46)
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

#Preview("Personalizza") {
    CustomizeOggi().previewEnvironment()
}

#Preview("Nuovo stile") {
    NewLookSheet(copying: TodayStyle.presets[3]) { _ in }
}

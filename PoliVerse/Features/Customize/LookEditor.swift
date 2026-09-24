import SwiftUI

/// Personalizza's editor: the page at full size, as the Lock Screen's editor
/// shows the wallpaper.
///
/// Every part of the page is an outlined zone, and a tap opens that part's
/// controls alone, in a small sheet that leaves the page live above it.
/// Swiping sideways runs through the five fixed lights — the way a photo
/// wallpaper swipes through its styles. The Flavor sits bottom-left, and
/// everything without a zone of its own is behind •••: the app half, the paper,
/// the cards, the sections, the name.
///
/// It edits a draft. Aggiungi or Fine keeps it, Annulla drops it, and
/// Ripristina, in the menu, goes back to where editing started.
struct LookEditor: View {
    /// The draft being edited.
    @Binding var look: TodayStyle
    /// The look as editing found it, for Ripristina and for asking before Annulla.
    let original: TodayStyle
    /// True for a look being added: its button says Aggiungi.
    let isNew: Bool
    /// The screen's safe area, so the controls clear the bars.
    let insets: EdgeInsets
    /// Leaves without keeping anything.
    let cancel: () -> Void
    /// Keeps the draft.
    let done: () -> Void
    /// Opens the look's app half.
    let openApp: () -> Void

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The part of the look whose controls are open, if any.
    @State private var panel: CustomizePage?
    /// Pages pushed inside the open panel, such as the sticker picker.
    @State private var panelPath: [CustomizePage] = []
    @State private var arranging = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingCancel = false
    /// The first-time hint about swiping, gone after a moment.
    @State private var showsHint = true
    /// A sideways swipe is under way. A zone is a button, and a button fires
    /// on any release inside it, so the swipe that crossed it must not open it.
    @State private var swiping = false
    /// Which page a special Flavor is previewed on.
    @State private var preview = SpecialPreview.today

    /// The lights a swipe runs through, in order: the page's styles.
    static let variants: [TodayAppearance] = [.system, .tinted, .contrast, .dark, .light]

    /// The light the page is drawn in: the look's own, or the system's.
    private var lit: ColorScheme { look.appearance.colorScheme ?? scheme }

    /// The view's content.
    var body: some View {
        ZStack {
            page
            controls
        }
        .sheet(item: $panel) { root in
            panelSheet(root)
        }
        .onChange(of: arranging) { _, arranging in
            if arranging { panel = nil }
        }
        .alert("Nome del Flavor", isPresented: $renaming) {
            TextField("Flavor", text: $newName)
                .accessibilityIdentifier("customize-name-field")
            Button("Annulla", role: .cancel) {}
            Button("Salva") { look.name = newName.trimmingCharacters(in: .whitespaces) }
        }
        .confirmationDialog("Annullare le modifiche?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Scarta le modifiche", role: .destructive, action: cancel)
                .accessibilityIdentifier("customize-editor-discard")
        }
        .sensoryFeedback(.selection, trigger: look.appearance)
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut) { showsHint = false }
        }
    }

    // MARK: - The page

    /// The page being edited, or — for a special Flavor — another tab
    /// wearing it, as the app will draw it.
    @ViewBuilder
    private var page: some View {
        if look.special != nil, preview != .today {
            otherPage
        } else {
            todayPage
        }
    }

    /// Corsi, Carriera or Cerca in the draft look: the real pages, drawn but
    /// not touchable, so a tap anywhere opens the Flavor's knobs again.
    private var otherPage: some View {
        let drawn = look.resolved
        return NavigationStack {
            Group {
                switch preview {
                case .courses: NewDestination.courses.screen
                case .career: NewDestination.career.screen
                case .search, .today: SearchView(embedded: true, places: NewDestination.inSearch)
                }
            }
            .flavorPaper()
        }
        .padding(.top, insets.top + 40)
        .background { LookBackground(style: drawn).ignoresSafeArea() }
        .environment(\.look, drawn)
        .tint(drawn.controlTint(lit))
        .environment(\.colorScheme, lit)
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { open(.special) }
                .accessibilityLabel(Text("Regola il Flavor"))
                .accessibilityAddTraits(.isButton)
        }
        .transition(.opacity)
    }

    /// Oggi itself, live: zones outlined, each a way into its controls.
    private var todayPage: some View {
        ScrollView {
            TodayLanding(day: shell.day, draft: $look, arranging: arranging,
                         onAddSticker: { open(.accessory, then: .stickerPicker) }) { zone in
                guard !arranging, !swiping else { return }
                // A special Flavor has no classic parts to open: every zone is its panel.
                open(look.special == nil ? CustomizePage(zone: zone) : .special)
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 56)
            .padding(.bottom, arranging ? 120 : 200)
        }
        .scrollIndicators(.hidden)
        .background { LookBackground(style: look.resolved).ignoresSafeArea() }
        .tint(look.resolved.controlTint(lit))
        // The look's own light on the page alone: the controls over it keep
        // theirs readable against whatever the page turns into.
        .environment(\.colorScheme, lit)
        .simultaneousGesture(variantSwipe)
        .sensoryFeedback(.impact(weight: .medium), trigger: arranging) { _, new in new }
    }

    /// A sideways swipe anywhere on the page steps to the next light.
    private var variantSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) { swiping = true }
            }
            .onEnded { value in
                // Cleared a moment later: the zone's button hears the same release.
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    swiping = false
                }
                guard !arranging, panel == nil else { return }
                let across = value.translation.width, down = value.translation.height
                guard abs(across) > 70, abs(across) > abs(down) * 2 else { return }
                step(across < 0 ? 1 : -1)
            }
    }

    /// Moves to a neighbouring light, stopping at either end.
    ///
    /// - Parameter offset: 1 for the next, -1 for the previous.
    private func step(_ offset: Int) {
        guard look.special != .blueprint else { return }
        let index = Self.variants.firstIndex(of: look.appearance) ?? 0
        let next = min(max(index + offset, 0), Self.variants.count - 1)
        guard next != index else { return }
        withAnimation(.snappy) { look.appearance = Self.variants[next] }
    }

    // MARK: - Controls

    /// The glass over the page: Annulla and Aggiungi or Fine at the top; the
    /// Flavor, the light and ••• at the bottom.
    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                if !arranging {
                    Button("Annulla") {
                        if look == original { cancel() } else { confirmingCancel = true }
                    }
                    .buttonStyle(.glass)
                    .tint(.primary)
                    .accessibilityIdentifier("customize-editor-cancel")
                }
                Spacer()
                if arranging {
                    Text("Disponi").font(.headline)
                    Spacer()
                }
                Button(arranging ? "Fine" : isNew ? "Aggiungi" : "Fine") {
                    if arranging {
                        withAnimation(.snappy) { arranging = false }
                    } else {
                        done()
                    }
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier(arranging ? "customize-arrange-done" : "customize-edit-done")
            }
            .padding(.horizontal, 20)
            .padding(.top, insets.top + 4)

            if showsHint, !arranging, look.special != .blueprint {
                Text("Scorri di lato per cambiare la luce")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            Spacer()

            if !arranging {
                HStack {
                    Button { open(look.special == nil ? .flavor : .special) } label: {
                        Circle()
                            .fill(look.resolved.flavor.base.color)
                            .frame(width: 26, height: 26)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Colore")
                    .accessibilityIdentifier("customize-editor-flavor")

                    Spacer()
                    // Blueprint is always dark: there is no light to swipe through.
                    if look.special != .blueprint { lightIndicator }
                    Spacer()

                    Menu { menuItems } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 52)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Altro")
                    .accessibilityIdentifier("customize-editor-more")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, insets.bottom + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Readable on the page whatever its light: primary for the plain
        // buttons, the look's accent in that light for Fine.
        .environment(\.colorScheme, lit)
        .tint(look.resolved.controlTint(lit))
        .animation(.snappy, value: arranging)
    }

    /// The light's name and a dot for each, as the Lock Screen names a photo's style.
    private var lightIndicator: some View {
        let index = Self.variants.firstIndex(of: look.appearance) ?? 0
        return VStack(spacing: 6) {
            Text(look.appearance.title)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
            HStack(spacing: 6) {
                ForEach(Self.variants.indices, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Luce")
        .accessibilityValue(Text(look.appearance.title))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("customize-light")
    }

    /// Everything without a zone on the page: the app half first, then the
    /// page's materials, its sections, and the look itself. System menu items
    /// drop accessibility identifiers, so tests find these by their labels.
    @ViewBuilder
    private var menuItems: some View {
        Button(action: openApp) {
            Label("App", systemImage: "apps.iphone")
            Text(look.app.paired ? "Abbinata a Oggi" : "Su misura")
        }
        if look.special != nil {
            Section {
                Button("Regola il Flavor", systemImage: "slider.horizontal.3") { open(.special) }
                Button("Duplica come classico", systemImage: "square.on.square") { duplicateAsClassic() }
            }
        } else {
            classicMenuItems
        }
        Section {
            Button("Rinomina", systemImage: "pencil") {
                newName = look.name
                renaming = true
            }
            Button("Ripristina", systemImage: "arrow.uturn.backward") {
                withAnimation(.snappy) { look = original }
            }
            .disabled(look == original)
        }
    }

    /// A classic Flavor's parts that have no zone on the page.
    @ViewBuilder
    private var classicMenuItems: some View {
        Section {
            Button("Carta e motivo", systemImage: "doc.richtext") { open(.paper) }
            Button("Superficie delle schede", systemImage: "square.on.square") { open(.cards) }
            Button("Aspetto e testo", systemImage: "textformat") { open(.appearance) }
        }
        Section {
            Button("Disponi le sezioni", systemImage: "square.stack.3d.up") {
                withAnimation(.snappy) { arranging = true }
            }
            Button("Sezioni", systemImage: "list.bullet") { open(.layout) }
        }
    }

    /// Turns a special Flavor into a classic one that keeps the recipe's
    /// colours and typefaces, with every part of it the student's again.
    private func duplicateAsClassic() {
        panel = nil
        // A classic Flavor has only Oggi to edit.
        preview = .today
        withAnimation(.snappy) {
            look = look.resolved
            look.special = nil
            look.specialSettings = SpecialSettings()
        }
    }

    // MARK: - Panels

    /// Opens one part's controls, optionally with a page pushed on top.
    ///
    /// - Parameters:
    ///   - page: The part.
    ///   - next: A page to push over it straight away.
    private func open(_ page: CustomizePage, then next: CustomizePage? = nil) {
        panelPath = next.map { [$0] } ?? []
        panel = page
    }

    /// One part's controls in a sheet: low enough that the page stays in sight
    /// and live, taller for a section, whose forms are cards to swipe through.
    private func panelSheet(_ root: CustomizePage) -> some View {
        let isSection = if case .section = root { true } else { false }
        return NavigationStack(path: $panelPath) {
            panelPage(root)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { panel = nil }
                            .accessibilityIdentifier("customize-panel-close")
                    }
                }
                .navigationDestination(for: CustomizePage.self) { panelPage($0) }
        }
        .tint(look.resolved.controlTint(scheme))
        .presentationDetents(isSection ? [.large] : [.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    /// The controls for one part of the look.
    @ViewBuilder
    private func panelPage(_ page: CustomizePage) -> some View {
        switch page {
        case .section(let kind):
            SectionFormPicker(kind: kind, style: $look, close: { panel = nil })
        case .special:
            SpecialFlavorControls(style: $look, preview: $preview.animation(.snappy),
                                  duplicateAsClassic: duplicateAsClassic)
        case .stickerPicker:
            StickerPicker(remaining: TodayStyle.maxStickers - look.stickers.count) { content in
                withAnimation(.snappy) { _ = look.addSticker(content) }
            }
        default:
            CustomizeControls(page: page, style: $look, arranging: $arranging,
                              pickStickers: { panelPath.append(.stickerPicker) })
        }
    }
}

import SwiftUI

/// Personalizza's editor: the page live and small in the middle, the look's
/// parts around it.
///
/// **iPhone.** Opening on the overview, every part is a card with a picture of
/// what it is now; a card, or a tap on that part of the page, opens its tools
/// under the page. A capsule at the bottom runs through the parts the way
/// Safari's runs through tabs, with the part's reset on its left and the way
/// back to every part on its right.
///
/// **iPad and Mac.** The parts are a sidebar on the left, which folds down to
/// their pictures; the open part's tools are an inspector on the right, its
/// reset at the bottom; the page sits between them, on the iPhone or at this
/// screen's size. Standing up, the parts run in a row along the top and the
/// inspector goes under the page.
///
/// The page stays live throughout, touches included: a tap on the date opens
/// Data, stickers drag where they are. It edits a draft. ✓ keeps it, ✕ drops
/// it, and every change can be undone — ⌘Z and ⇧⌘Z from a keyboard.
struct LookEditor: View {
    /// The draft being edited.
    @Binding var look: TodayStyle
    /// The look as editing found it, for the resets and for asking before ✕.
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
    /// Regular on iPad and Mac, where the parts and tools sit beside the page.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The sidebar shows each part's name and value, not only its picture.
    @AppStorage("lookEditorSidebarOpen") private var sidebarOpen = true
    /// What the page is previewed on, on iPad and Mac.
    @State private var device = PreviewDevice.screen
    /// The part whose tools are open, or `nil` for the overview.
    @State private var part: LookPart?
    /// The tool each part last showed, so coming back finds it again.
    @State private var tools: [LookPart: CustomizePage] = [:]
    /// What is up in a sheet of its own: a section's card or the sticker picker.
    @State private var sheet: CustomizePage?
    @State private var arranging = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingCancel = false
    /// Which page a special Flavor is previewed on.
    @State private var preview = SpecialPreview.today
    /// Every change, to undo and redo.
    @State private var history = EditHistory()
    /// False while the card that opened the editor is still growing into it:
    /// the page starts at full size and settles into the middle.
    @State private var settled = false

    /// The lights the Luce tool runs through, in order: the page's styles.
    static let variants: [TodayAppearance] = [.system, .tinted, .contrast, .dark, .light]

    /// The tools' height under the page, as a share of the screen's.
    private static let toolsShare: CGFloat = 0.3
    /// The editor's coordinate space, where the page finds the screen's middle.
    private static let space = "look-editor"
    /// The inspector's width beside the page.
    private static let inspectorWidth: CGFloat = 340

    /// What the page is previewed on, on iPad and Mac.
    enum PreviewDevice: Hashable {
        /// An iPhone, as most students will see it.
        case phone
        /// This screen: the iPad's, or the Mac's window.
        case screen
    }

    /// A screen the page is drawn on: its size and safe area, its corners, and
    /// whether it has the iPhone's tab bar floating at the bottom.
    private struct Screen {
        var size: CGSize
        var insets: EdgeInsets
        var cornerRadius: CGFloat
        var tabBar: Bool
    }

    /// The light the page is drawn in: the look's own, or the system's.
    private var lit: ColorScheme { look.appearance.colorScheme ?? scheme }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            // The whole screen: the host already reaches under the bars.
            let screen = proxy.size
            Group {
                if sizeClass == .regular {
                    wide(screen: screen)
                } else {
                    compact(screen: screen)
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .top)
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea()
        .background(Color.black)
        // The editor's own controls are always on black; the page keeps its own light.
        .environment(\.colorScheme, .dark)
        .tint(look.resolved.controlTint(.dark))
        .animation(.snappy, value: part)
        .animation(.snappy, value: arranging)
        .animation(.snappy, value: sidebarOpen)
        .animation(.snappy, value: device)
        .sheet(item: $sheet) { page in
            sheetContent(page)
        }
        .onChange(of: look) { old, _ in
            history.record(old)
        }
        .onChange(of: look.special) { _, special in
            // Crossing between a classic look and a special Flavor changes the parts.
            if let part, !LookPart.parts(for: look).contains(part) {
                self.part = special == nil ? .theme : .special
            }
            if special == nil { preview = .today }
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
        .sensoryFeedback(.selection, trigger: part)
        .sensoryFeedback(.impact(weight: .medium), trigger: arranging) { _, new in new }
        .onAppear {
            withAnimation(.smooth(duration: 0.45)) { settled = true }
        }
    }

    // MARK: - iPhone

    /// The bar, the page, and under it the overview or the open part.
    private func compact(screen: CGSize) -> some View {
        VStack(spacing: 0) {
            topBar(showsName: false)
                .padding(.horizontal, 16)
                .padding(.top, insets.top + 4)
                .opacity(settled ? 1 : 0)
            page(on: Screen(size: screen, insets: insets, cornerRadius: 48, tabBar: !shell.singlePage), screen: screen)
                .padding(.vertical, 12)
            if !arranging {
                lower(screen: screen)
                    .opacity(settled ? 1 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - iPad and Mac

    /// The part open beside the page: there is no overview here, so Tema
    /// until another is chosen.
    private var widePart: LookPart {
        if let part, part != .app, LookPart.parts(for: look).contains(part) { return part }
        return .theme
    }

    /// The screen the page is previewed on.
    private func previewScreen(_ screen: CGSize) -> Screen {
        switch device {
        case .phone:
            Screen(size: LookScreen.reference, insets: LookScreen.referenceInsets, cornerRadius: 48, tabBar: !shell.singlePage)
        case .screen:
            // A sidebar rather than a tab bar at this width.
            Screen(size: screen, insets: insets, cornerRadius: 24, tabBar: false)
        }
    }

    /// Lying down, the parts on the left, the page in the middle and the
    /// inspector on the right; standing up, the parts along the top and the
    /// inspector under the page.
    private func wide(screen: CGSize) -> some View {
        let landscape = screen.width > screen.height
        return VStack(spacing: 0) {
            topBar(showsName: true)
                .padding(.horizontal, 20)
                .padding(.top, insets.top + 8)
                .padding(.bottom, 4)
                .opacity(settled ? 1 : 0)
            if landscape {
                HStack(spacing: 0) {
                    if !arranging {
                        sidebar
                            .opacity(settled ? 1 : 0)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    stage(screen: screen)
                    if !arranging {
                        inspector(themeColumns: 3)
                            .frame(width: Self.inspectorWidth)
                            .opacity(settled ? 1 : 0)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, max(insets.bottom, 12))
            } else {
                VStack(spacing: 0) {
                    if !arranging {
                        partRow
                            .opacity(settled ? 1 : 0)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    stage(screen: screen)
                    if !arranging {
                        inspector(themeColumns: 0)
                            .frame(height: screen.height * 0.4)
                            .opacity(settled ? 1 : 0)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, max(insets.bottom, 12))
            }
        }
    }

    /// The page, and under it what it is previewed on.
    private func stage(screen: CGSize) -> some View {
        VStack(spacing: 12) {
            page(on: previewScreen(screen), screen: screen)
            if !arranging {
                GlassSegmentedPicker("Anteprima su", selection: $device, options: [.phone, .screen]) { device in
                    switch device {
                    case .phone: Text(verbatim: "iPhone")
                    case .screen: Text(verbatim: ProcessInfo.processInfo.isiOSAppOnMac ? "Mac" : "iPad")
                    }
                }
                .frame(maxWidth: 260)
                .opacity(settled ? 1 : 0)
                .accessibilityIdentifier("customize-preview-device")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The parts down the left, each with its picture; folded, only the pictures.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                sidebarOpen.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .keyboardShortcut("s", modifiers: [.command, .control])
            .help(sidebarOpen ? Text("Riduci la barra laterale") : Text("Espandi la barra laterale"))
            .accessibilityLabel(sidebarOpen ? Text("Riduci la barra laterale") : Text("Espandi la barra laterale"))
            .accessibilityIdentifier("customize-sidebar-toggle")

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(LookPart.parts(for: look)) { part in
                        sidebarRow(part)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(10)
        .frame(width: sidebarOpen ? 260 : 76, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Parti del Flavor")
    }

    /// One part in the sidebar.
    private func sidebarRow(_ part: LookPart) -> some View {
        let chosen = part == widePart
        return Button { show(part) } label: {
            HStack(spacing: 12) {
                LookPartThumbnail(part: part, look: look, side: 44)
                if sidebarOpen {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        LookPartValue(part: part, look: look)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if chosen { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)) }
            }
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .help(Text(part.title))
        .accessibilityLabel(Text(part.title))
        .accessibilityIdentifier("customize-part-\(part.id)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Standing up, the parts in a row along the top.
    private var partRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(LookPart.parts(for: look)) { part in
                    let chosen = part == widePart
                    Button { show(part) } label: {
                        VStack(spacing: 4) {
                            LookPartThumbnail(part: part, look: look, side: 44)
                            Text(part.title)
                                .font(.caption.weight(chosen ? .semibold : .regular))
                                .foregroundStyle(chosen ? .primary : .secondary)
                        }
                        .padding(6)
                        .background {
                            if chosen { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)) }
                        }
                        .contentShape(.rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier("customize-part-\(part.id)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Parti del Flavor")
    }

    /// The open part's name and value, its tools, and its reset at the bottom.
    private func inspector(themeColumns: Int) -> some View {
        let part = widePart
        let reset = part.reset(look, to: original)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                LookPartValue(part: part, look: look)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            partTools(part, boxed: false, themeColumns: themeColumns)
                .frame(maxHeight: .infinity, alignment: .top)

            Button {
                withAnimation(.snappy) { look = reset }
            } label: {
                Text(part.resetTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(reset == look)
            .padding(16)
            .accessibilityIdentifier("customize-part-reset")
        }
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 28, style: .continuous))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Top bar

    /// ✕, undo and redo on the left; ••• and ✓ on the right; on iPad and Mac
    /// the look's name between them. Arranging, only the mode's name and Fine.
    ///
    /// - Parameter showsName: Puts the look's name in the middle.
    private func topBar(showsName: Bool) -> some View {
        HStack(spacing: 8) {
            if arranging {
                Spacer()
                Text("Disponi").font(.headline)
                Spacer()
                Button("Fine") { arranging = false }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("customize-arrange-done")
            } else {
                roundButton("Annulla", symbol: "xmark", id: "customize-editor-cancel", shortcut: .cancelAction) {
                    if look == original { cancel() } else { confirmingCancel = true }
                }
                roundButton("Annulla modifica", symbol: "arrow.uturn.backward", id: "customize-editor-undo",
                            shortcut: KeyboardShortcut("z", modifiers: .command), action: undo)
                    .disabled(!history.canUndo)
                roundButton("Ripeti modifica", symbol: "arrow.uturn.forward", id: "customize-editor-redo",
                            shortcut: KeyboardShortcut("z", modifiers: [.command, .shift]), action: redo)
                    .disabled(!history.canRedo)
                Spacer()
                if showsName {
                    nameButton(font: .headline)
                    Spacer()
                }
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Altro")
                .accessibilityIdentifier("customize-editor-more")
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(isNew ? "Aggiungi" : "Fine")
                .accessibilityIdentifier("customize-edit-done")
            }
        }
        .frame(height: 48)
    }

    /// A round glass button with a symbol.
    private func roundButton(_ label: LocalizedStringKey, symbol: String, id: String,
                             shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .keyboardShortcut(shortcut)
        .help(Text(label))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// The look's name, which a tap renames.
    private func nameButton(font: Font) -> some View {
        Button(action: rename) {
            HStack(spacing: 6) {
                if look.name.isEmpty {
                    Text("Senza nome")
                } else {
                    Text(verbatim: look.name)
                }
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Rinomina"))
        .accessibilityValue(Text(verbatim: look.name))
        .accessibilityIdentifier("customize-editor-name")
    }

    /// The look itself: its name, arranging its sections, starting over.
    /// System menu items drop accessibility identifiers, so tests find these
    /// by their labels.
    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button("Rinomina", systemImage: "pencil", action: rename)
            if look.special == nil {
                Button("Disponi le sezioni", systemImage: "square.stack.3d.up") { arranging = true }
            } else {
                Button("Duplica come classico", systemImage: "square.on.square") { duplicateAsClassic() }
            }
        }
        Section {
            Button("Ripristina", systemImage: "arrow.uturn.backward") {
                withAnimation(.snappy) { look = original }
            }
            .disabled(look == original)
        }
    }

    /// Asks for a new name.
    private func rename() {
        newName = look.name
        renaming = true
    }

    /// Goes back one change.
    private func undo() {
        guard let previous = history.undo(from: look) else { return }
        withAnimation(.snappy) { look = previous }
    }

    /// Goes forward one change again.
    private func redo() {
        guard let next = history.redo(from: look) else { return }
        withAnimation(.snappy) { look = next }
    }

    // MARK: - The page

    /// The page as the app will show it, drawn at its screen's size and
    /// scaled to the room left for it.
    ///
    /// - Parameters:
    ///   - target: The screen the page is drawn on.
    ///   - screen: The editor's own screen, which the page covers before settling.
    private func page(on target: Screen, screen: CGSize) -> some View {
        Color.clear
            .overlay {
                GeometryReader { room in
                    let size = target.size
                    let fit = min(room.size.height / size.height, room.size.width / size.width)
                    // Before settling, the page covers the screen, where the card left it.
                    let cover = max(screen.width / size.width, screen.height / size.height)
                    let frame = room.frame(in: .named(Self.space))
                    let toScreen = CGSize(width: screen.width / 2 - frame.midX, height: screen.height / 2 - frame.midY)
                    livePage(on: target)
                        .clipShape(.rect(cornerRadius: target.cornerRadius * (settled ? 1 : 0), style: .continuous))
                        .scaleEffect(settled ? fit : cover)
                        .frame(width: room.size.width, height: room.size.height)
                        .offset(settled ? .zero : toScreen)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Laid out at full size, shown smaller: the page takes only the room of its scaled copy.
            .zIndex(1)
    }

    /// The page at full size, live.
    private func livePage(on target: Screen) -> some View {
        Group {
            if look.special != nil, preview != .today {
                otherPage(insets: target.insets)
            } else {
                todayPage(insets: target.insets)
            }
        }
        .frame(width: target.size.width, height: target.size.height, alignment: .top)
        .background { LookBackground(style: look.resolved) }
        .overlay(alignment: .bottom) {
            if target.tabBar {
                ReplicaTabBar()
                    .padding(.bottom, max(target.insets.bottom - 13, 0))
                    .allowsHitTesting(false)
            }
        }
        .tint(look.resolved.controlTint(lit))
        .environment(\.colorScheme, lit)
    }

    /// Oggi itself, live: every part a way into its tools, marked by nothing
    /// but the page itself.
    private func todayPage(insets: EdgeInsets) -> some View {
        ScrollView {
            TodayLanding(day: shell.day, draft: $look, arranging: arranging, quiet: true,
                         onAddSticker: { sheet = .stickerPicker }) { zone in
                guard !arranging else { return }
                open(zone)
            }
            .padding(.top, insets.top)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    /// Corsi, Carriera or Cerca in the draft look: the real pages, drawn but
    /// not touchable, so a tap anywhere opens the Flavor's knobs again.
    private func otherPage(insets: EdgeInsets) -> some View {
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
        .padding(.top, insets.top)
        .environment(\.look, drawn)
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { showTool(.special) }
                .accessibilityLabel(Text("Regola il Flavor"))
                .accessibilityAddTraits(.isButton)
        }
        .transition(.opacity)
    }

    // MARK: - Under the page

    /// The overview, or the open part's tools and the capsule.
    @ViewBuilder
    private func lower(screen: CGSize) -> some View {
        if let part {
            VStack(spacing: 10) {
                partTools(part)
                    .frame(height: screen.height * Self.toolsShare)
                switcher(part)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, insets.bottom + 4)
        } else {
            overview
                .padding(.horizontal, 16)
                .padding(.bottom, insets.bottom + 8)
        }
    }

    /// Every part at once: the look's name, then a card for each part.
    private var overview: some View {
        VStack(spacing: 12) {
            nameButton(font: .title3.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(LookPart.parts(for: look)) { part in
                    Button { show(part) } label: {
                        LookPartCard(part: part, look: look)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-part-\(part.id)")
                }
            }

            Text("Oppure tocca una parte dell’anteprima.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The open part's tools: tabs when it has more than one, then the
    /// controls of the one chosen.
    ///
    /// - Parameters:
    ///   - part: The part.
    ///   - boxed: Sets the controls on a panel of their own, as under the
    ///     page on iPhone; the inspector is one already.
    ///   - themeColumns: Columns of themes, or 0 for a row.
    @ViewBuilder
    private func partTools(_ part: LookPart, boxed: Bool = true, themeColumns: Int = 0) -> some View {
        switch part {
        case .theme:
            ThemePicker(look: $look, columns: themeColumns)
                .frame(maxHeight: .infinity, alignment: .top)
        case .app:
            // App has an editor of its own; the capsule opens it rather than this.
            EmptyView()
        default:
            VStack(spacing: 8) {
                if part.tools.count > 1 {
                    GlassSegmentedPicker("Strumenti", selection: toolBinding(part), options: part.tools) { page in
                        Text(page.title)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("customize-tools")
                }
                toolPage(tool(of: part))
                    .id(tool(of: part))
                    .scrollContentBackground(.hidden)
                    .background(.white.opacity(boxed ? 0.06 : 0), in: .rect(cornerRadius: 28, style: .continuous))
                    .clipShape(.rect(cornerRadius: boxed ? 28 : 0, style: .continuous))
                    .padding(.horizontal, boxed ? 12 : 0)
            }
        }
    }

    /// The tool a part shows: the one last chosen there, or its first.
    private func tool(of part: LookPart) -> CustomizePage {
        tools[part] ?? part.tools.first ?? .flavor
    }

    /// The tabs' selection for a part.
    private func toolBinding(_ part: LookPart) -> Binding<CustomizePage> {
        Binding { tool(of: part) } set: { tools[part] = $0 }
    }

    /// One page of controls. A page one of them opens — a section's card —
    /// comes up in a sheet rather than inside the tools, which are too low for it.
    @ViewBuilder
    private func toolPage(_ page: CustomizePage) -> some View {
        switch page {
        case .special:
            SpecialFlavorControls(style: $look, preview: $preview.animation(.snappy),
                                  duplicateAsClassic: duplicateAsClassic)
        default:
            NavigationStack(path: Binding<[CustomizePage]> { [] } set: { pushed in
                if let next = pushed.last { sheet = next }
            }) {
                CustomizeControls(page: page, style: $look, arranging: $arranging,
                                  pickStickers: { sheet = .stickerPicker })
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: CustomizePage.self) { _ in EmptyView() }
            }
        }
    }

    /// The capsule: the part's reset on the left, every part's name in the
    /// middle, the way back to all of them on the right.
    private func switcher(_ current: LookPart) -> some View {
        let reset = current.reset(look, to: original)
        return HStack(spacing: 10) {
            roundButton(current.resetTitle, symbol: "arrow.counterclockwise", id: "customize-part-reset") {
                withAnimation(.snappy) { look = reset }
            }
            .disabled(reset == look)

            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(LookPart.parts(for: look)) { part in
                            let chosen = part == current
                            Button { show(part) } label: {
                                Text(part.title)
                                    .font(.subheadline.weight(chosen ? .semibold : .regular))
                                    .foregroundStyle(chosen ? .primary : .secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background {
                                        if chosen { Capsule().fill(.white.opacity(0.14)) }
                                    }
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .id(part)
                            .accessibilityIdentifier("customize-switch-\(part.id)")
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 5)
                }
                .scrollIndicators(.hidden)
                .onAppear { reader.scrollTo(current, anchor: .center) }
                .onChange(of: current) { _, part in
                    withAnimation(.snappy) { reader.scrollTo(part, anchor: .center) }
                }
            }
            .frame(height: 48)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Parti del Flavor")

            roundButton("Tutte le parti", symbol: "square.grid.2x2", id: "customize-parts") {
                part = nil
            }
        }
    }

    // MARK: - Opening

    /// Opens a part: its tools, or the app's own editor for App.
    private func show(_ next: LookPart) {
        if next == .app {
            openApp()
        } else {
            part = next
        }
    }

    /// Opens a part on one of its tools.
    private func showTool(_ page: CustomizePage) {
        guard let owner = LookPart(page: page) else {
            sheet = page
            return
        }
        tools[owner] = page
        part = owner
    }

    /// Opens what a tap on the page means: its part's tools, or a section's card.
    private func open(_ zone: TodayLanding.Zone) {
        if let opening = LookPart.opening(zone, in: look) {
            tools[opening.part] = opening.page
            part = opening.part
        } else if case .section(let kind) = zone {
            sheet = .section(kind)
        }
    }

    /// Turns a special Flavor into a classic one that keeps the recipe's
    /// colours and typefaces, with every part of it the student's again.
    private func duplicateAsClassic() {
        // A classic Flavor has only Oggi to edit.
        preview = .today
        withAnimation(.snappy) {
            look = look.resolved
            look.special = nil
            look.specialSettings = SpecialSettings()
        }
        part = .colour
    }

    // MARK: - Sheets

    /// A section's card, tall, since its forms are cards to swipe through;
    /// or the sticker picker.
    @ViewBuilder
    private func sheetContent(_ page: CustomizePage) -> some View {
        switch page {
        case .section(let kind):
            NavigationStack {
                SectionFormPicker(kind: kind, style: $look, close: { sheet = nil })
                    .toolbar { closeItem }
            }
            .tint(look.resolved.controlTint(scheme))
            .presentationDetents([.large])
        default:
            NavigationStack {
                StickerPicker(remaining: TodayStyle.maxStickers - look.stickers.count) { content in
                    withAnimation(.snappy) { _ = look.addSticker(content) }
                }
                .toolbar { closeItem }
            }
            .tint(look.resolved.controlTint(scheme))
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
        }
    }

    /// The close button of a sheet.
    private var closeItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .close) { sheet = nil }
                .accessibilityIdentifier("customize-panel-close")
        }
    }
}

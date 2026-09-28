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
/// App is a part like the others: while its icon or colour is open, the page
/// gives way to a Home Screen with the icon on it.
///
/// **iPad and Mac.** The parts are a sidebar on the left, which folds down to
/// their pictures; the open part's tools are an inspector on the right, its
/// reset at the bottom; the page sits between them, on the iPhone or at this
/// screen's size. Standing up, the parts run in a row along the top and the
/// inspector goes under the page. For App the inspector holds every tool at
/// once, and a switch under the page shows the Home Screen — the Dock on a
/// Mac — or Oggi.
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
    /// Deletes the look, for one already saved that is not the last.
    var delete: (() -> Void)?
    /// Where the gallery's card of the look is, for an edit: the page moves
    /// from there into its place on opening, and back there on leaving.
    var origin: CGRect?

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// Regular on iPad and Mac, where the parts and tools sit beside the page.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The sidebar shows each part's name and value, not only its picture.
    @AppStorage("lookEditorSidebarOpen") private var sidebarOpen = true
    /// What the page is previewed on, on iPad and Mac: this kind of screen to begin with.
    @State private var device = LookEditor.ownDevice
    /// The iPhone task under way, if any.
    @State private var mode: EditorMode?
    /// The look as the task found it, for its Annulla.
    @State private var modeSnapshot: TodayStyle?
    /// The stickers' task has the keyboard open to add more.
    @State private var addingSticker = false
    @State private var confirmingDelete = false
    /// The name field in the overview, which Rinomina puts the cursor in.
    @FocusState private var nameFocused: Bool
    /// A text field in the tools has the keyboard: the stickers' keys stand down.
    @State private var typingInTools = false
    /// Where the keyboard's top edge is while it is up. The editor reaches
    /// under every bar, the keyboard's included, so it makes room itself.
    @State private var keyboardTop: CGFloat?
    /// With App open on iPad and Mac, whether the Home Screen or Oggi is shown.
    @State private var appView = AppView.home
    /// How the Home Screen previewed for App draws its icons.
    @State private var homeLook = AppPreview.HomeLook.light
    /// The part whose tools are open, or `nil` for the overview.
    @State private var part: LookPart?
    /// The tool each part last showed, so coming back finds it again.
    @State private var tools: [LookPart: LookTool] = [:]
    /// What is up in a sheet of its own: a section's card or the sticker picker.
    @State private var sheet: CustomizePage?
    /// The sticker selected on the page: ringed, with its handle, its actions
    /// in Saluto's Accessorio and on the keyboard.
    @State private var selectedSticker: UUID?
    @State private var arranging = false
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

    /// The most of the screen the overview or a part's tools take under the page.
    private static let lowerShare: CGFloat = 0.46
    /// The editor's coordinate space, where the page finds the screen's middle.
    private static let space = "look-editor"
    /// The inspector's width beside the page.
    private static let inspectorWidth: CGFloat = 340

    /// What the page is previewed on, on iPad and Mac.
    enum PreviewDevice: Hashable, CaseIterable {
        /// An iPhone, as most students will see it.
        case phone
        /// An iPad, lying down.
        case pad
        /// A Mac's window.
        case mac

        /// What the switch calls it.
        var title: String {
            switch self {
            case .phone: "iPhone"
            case .pad: "iPad"
            case .mac: "Mac"
            }
        }
    }

    /// What App shows beside its tools on iPad and Mac.
    enum AppView: Hashable {
        /// The Home Screen, or the Mac's Dock, with the icon.
        case home
        /// Oggi, in the app's colour.
        case today
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
                if isWide {
                    wide(screen: screen)
                } else {
                    compact(screen: screen)
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .top)
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea()
        // The gallery shows through while the page moves between its card and its place.
        .background(Color.black.opacity(arrived ? 1 : 0).ignoresSafeArea())
        // The editor's own controls are always on black; the page keeps its own light.
        .environment(\.colorScheme, .dark)
        .tint(look.resolved.controlTint(.dark))
        .animation(.snappy, value: part)
        .animation(.snappy, value: arranging)
        .animation(.snappy, value: sidebarOpen)
        .animation(.snappy, value: device)
        .animation(.snappy, value: mode)
        .sheet(item: $sheet) { page in
            sheetContent(page)
        }
        .onChange(of: look) { old, _ in
            history.record(old)
        }
        // The selection goes with the stickers' tool, and with the sticker.
        .onChange(of: stickerToolOpen) { _, open in
            if !open { selectedSticker = nil }
        }
        .onChange(of: look.stickers) { _, stickers in
            if let id = selectedSticker, !stickers.contains(where: { $0.id == id }) { selectedSticker = nil }
        }
        .background { stickerKeys }
        // The Mac has no software keyboard to make room for.
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.snappy) { keyboardTop = frame.minY }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.snappy) { keyboardTop = nil }
        }
        #endif
        .onChange(of: look.special) { _, special in
            // Crossing between a classic look and a special Flavor changes the parts.
            if let part, !LookPart.parts(for: look).contains(part) {
                self.part = special == nil ? .theme : .special
            }
            if special == nil { preview = .today }
        }
        .modifier(DiscardQuestion(onMac: Self.onMac && isWide, isPresented: $confirmingCancel,
                                  name: look.name, discard: { leave(then: cancel) }))
        .confirmationDialog("Eliminare il Flavor?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Elimina Flavor", role: .destructive) {
                if let delete { leave(then: delete) }
            }
                .accessibilityIdentifier("customize-editor-delete-confirm")
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Lo trovi di nuovo per qualche secondo, con Annulla nella galleria.")
        }
        .sensoryFeedback(.selection, trigger: part)
        .sensoryFeedback(.lift, trigger: arranging) { _, new in new }
        .onAppear {
            withAnimation(.smooth(duration: 0.45)) { settled = true }
        }
    }

    // MARK: - iPhone

    /// The bar, the page, and under it the overview or the open part.
    private func compact(screen: CGSize) -> some View {
        VStack(spacing: 0) {
            Group {
                if let mode {
                    ModeBar(mode: mode, cancel: cancelMode, done: finishMode)
                } else {
                    topBar
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 4)
            .opacity(arrived ? 1 : 0)
            page(on: Screen(size: screen, insets: insets, cornerRadius: 48, tabBar: !shell.singlePage), screen: screen,
                 home: part == .app && tool(of: .app) != .appBar && mode == nil ? .homeScreen : nil,
                 zoomed: mode != nil,
                 // The sections' task looks past the header, at the cards.
                 skip: mode == .sections ? insets.top + 240 : 0)
                .padding(.vertical, 12)
            if let mode {
                modeDock(mode, screen: screen)
                    .padding(.bottom, insets.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !arranging {
                lower(screen: screen)
                    .opacity(arrived ? 1 : 0)
                    // Typing the name, the controls rise over the page rather
                    // than squeezing it: it keeps its size.
                    .offset(y: -keyboardOverlap(screen))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // In a task the keyboard is part of it: the dock sits on it, and the
        // page, sized by its width, only shows less of itself.
        .padding(.bottom, mode != nil ? keyboardOverlap(screen) : 0)
    }

    /// How far the keyboard reaches over the bottom of the screen, beyond the
    /// home indicator's room the bottom controls already leave.
    private func keyboardOverlap(_ screen: CGSize) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return max(0, screen.height - keyboardTop - insets.bottom)
    }

    /// What a task docks at the bottom.
    @ViewBuilder
    private func modeDock(_ mode: EditorMode, screen: CGSize) -> some View {
        switch mode {
        case .stickers:
            StickerDock(look: $look, adding: $addingSticker)
        case .greeting:
            TypingDock(text: $look.customGreeting, prompt: "Scrivi il tuo saluto", limit: TodayStyle.customGreetingLimit,
                       note: "Sopra la data, al posto del saluto.", submit: finishMode)
        case .besideText:
            TypingDock(text: $look.accessoryText, prompt: "Tutto pronto?", limit: TodayStyle.accessoryTextLimit,
                       note: "Nel carattere della data e nel tuo colore.", submit: finishMode)
        case .sections:
            SectionTaskDock(look: $look)
                .frame(height: screen.height * 0.42)
        }
    }

    /// Starts a task, remembering the look to go back to.
    private func enter(_ next: EditorMode) {
        modeSnapshot = look
        switch next {
        case .sections:
            part = .cards
            tools[.cards] = .sections
        case .greeting:
            part = .greeting
            tools[.greeting] = .greeting
        case .stickers, .besideText:
            part = .greeting
            tools[.greeting] = .beside
        }
        addingSticker = next == .stickers && look.stickers.isEmpty
        withAnimation(.snappy) { mode = next }
    }

    /// Leaves the task, putting the look back as it began.
    private func cancelMode() {
        if let modeSnapshot { withAnimation(.snappy) { look = modeSnapshot } }
        endMode()
    }

    /// Leaves the task, keeping what it changed.
    private func finishMode() {
        endMode()
    }

    /// Clears what the task kept.
    private func endMode() {
        withAnimation(.snappy) {
            mode = nil
            modeSnapshot = nil
            addingSticker = false
            selectedSticker = nil
        }
    }

    // MARK: - iPad and Mac

    /// The part open beside the page: there is no overview here, so Tema
    /// until another is chosen.
    private var widePart: LookPart {
        if let part, LookPart.parts(for: look).contains(part) { return part }
        return .theme
    }

    /// The screen the page is previewed on.
    private func previewScreen(_ screen: CGSize) -> Screen {
        switch device {
        case .phone:
            Screen(size: LookScreen.reference, insets: LookScreen.referenceInsets, cornerRadius: 48, tabBar: !shell.singlePage)
        case .pad:
            // On an iPad, this one, as it is held; elsewhere one lying down. A
            // sidebar rather than a tab bar at this width.
            Self.onPad
                ? Screen(size: screen, insets: insets, cornerRadius: 18, tabBar: false)
                : Screen(size: CGSize(width: 1194, height: 834), insets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
                         cornerRadius: 18, tabBar: false)
        case .mac:
            // On a Mac, this window; elsewhere a laptop's, under its title bar.
            Self.onMac
                ? Screen(size: screen, insets: insets, cornerRadius: 10, tabBar: false)
                : Screen(size: CGSize(width: 1280, height: 800), insets: EdgeInsets(top: 28, leading: 0, bottom: 0, trailing: 0),
                         cornerRadius: 10, tabBar: false)
        }
    }

    /// Lying down, the parts on the left, the page in the middle and the
    /// inspector on the right; standing up, the parts along the top and the
    /// inspector under the page.
    private func wide(screen: CGSize) -> some View {
        let landscape = screen.width > screen.height
        return VStack(spacing: 0) {
            Group {
                if Self.onMac { macBar } else { padBar }
            }
                .padding(.horizontal, 20)
                .padding(.top, insets.top + 8)
                .padding(.bottom, 4)
                .opacity(arrived ? 1 : 0)
            if landscape {
                HStack(spacing: 0) {
                    if !arranging {
                        sidebar
                            .opacity(arrived ? 1 : 0)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    stage(screen: screen)
                    if !arranging {
                        inspector
                            // The keyboard shortens the inspector alone, not the page.
                            .padding(.bottom, keyboardOverlap(screen))
                            .frame(width: Self.inspectorWidth)
                            .opacity(arrived ? 1 : 0)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, max(insets.bottom, 12))
            } else {
                VStack(spacing: 0) {
                    if !arranging {
                        partRow
                            .opacity(arrived ? 1 : 0)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    stage(screen: screen)
                    if !arranging {
                        inspector
                            .frame(height: screen.height * 0.4)
                            // Rises over the page with the keyboard, which keeps its size.
                            .offset(y: -keyboardOverlap(screen))
                            .opacity(arrived ? 1 : 0)
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
            page(on: previewScreen(screen), screen: screen, home: wideHome)
            if !arranging {
                HStack(spacing: 12) {
                    if widePart == .app {
                        GlassSegmentedPicker("Mostra", selection: $appView, options: [.home, .today]) { view in
                            switch view {
                            case .home: wideHome == .dock ? Text("Dock") : Text("Schermata Home")
                            case .today: Text("Oggi")
                            }
                        }
                        .frame(maxWidth: 280)
                        .accessibilityIdentifier("customize-app-view")
                        .transition(.opacity)
                    }
                    GlassSegmentedPicker("Anteprima su", selection: $device, options: PreviewDevice.allCases) { device in
                        Text(verbatim: device.title)
                    }
                    .frame(maxWidth: 300)
                    .accessibilityIdentifier("customize-preview-device")
                }
                .opacity(arrived ? 1 : 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Whether this is the iPad app running on a Mac.
    static let onMac: Bool = {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }()

    /// Whether this is an iPad, and not the iPad app on a Mac.
    static let onPad: Bool = {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        false
        #endif
    }()

    /// This kind of device, which the preview starts on and hands back on leaving.
    static let ownDevice: PreviewDevice = onMac ? .mac : onPad ? .pad : .phone

    /// The iPad and Mac layout: the sidebar, the page and the inspector. A Mac's
    /// window has it whatever its width, and has no size class to say so.
    private var isWide: Bool { sizeClass == .regular || Self.onMac }

    /// Whether the page is in its place and the controls are showing. A new
    /// look slides up with the page already small; an edit starts on the
    /// gallery's card, and settles into its place.
    private var arrived: Bool { settled || isNew }

    /// Leaves the editor: an edit moves its page back onto the gallery's card,
    /// and then goes; a new look just goes.
    ///
    /// - Parameter action: Cancelling, keeping or deleting, once the page is back.
    private func leave(then action: @escaping () -> Void) {
        guard !isNew else {
            action()
            return
        }
        withAnimation(.smooth(duration: 0.35)) {
            // Back to this device's Oggi, which the card shows, as the page returns to it.
            mode = nil
            if !isWide { part = nil }
            appView = .today
            preview = .today
            device = Self.ownDevice
            settled = false
        } completion: {
            action()
        }
    }

    /// What App shows in place of the page: the Home Screen, or on a Mac's
    /// own screen its Dock; `nil` for the page.
    private var wideHome: AppPreview.Mode? {
        guard widePart == .app, appView == .home else { return nil }
        return device == .mac ? .dock : .homeScreen
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
            .pointerHighlight()
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
        .pointerHighlight()
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
                    .pointerHighlight()
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
    private var inspector: some View {
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

            Group {
                switch part {
                case .app:
                    appInspector
                case .special:
                    SpecialFlavorControls(style: $look, preview: $preview.animation(.snappy),
                                          duplicateAsClassic: duplicateAsClassic)
                        .scrollContentBackground(.hidden)
                default:
                    // Every tool of the part at once, as the design stacks them.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            // On iPad the name is set here; a Mac has it in the toolbar.
                            if part == .theme && !Self.onMac {
                                ToolGroup(title: "Nome") { nameField }
                            }
                            ForEach(part.tools) { tool in
                                ToolGroup(title: tool.inspectorTitle, note: tool.note) {
                                    toolView(tool, layout: .inspector)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
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

    /// App's tools all at once, as the inspector has room for: the icon, how
    /// the Home Screen draws it, the app's colour and the iPhone's tab bar.
    /// Changing the icon shows the Home Screen; changing the bar, Oggi on an iPhone.
    private var appInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                inspectorGroup("Icona", note: look.app.paired
                               ? "Automatica segue il colore del Flavor."
                               : "Scelta a mano. Automatica la riabbina al Flavor.") {
                    AppIconPicker(look: $look, layout: .grid(columns: 4))
                }
                inspectorGroup("Aspetto della Home", note: "Come la vedi con le icone scure, colorate o trasparenti.") {
                    GlassSegmentedPicker("Aspetto della Home", selection: $homeLook) { Text($0.title) }
                        .accessibilityIdentifier("customize-home-look")
                }
                inspectorGroup("Colore dell’app", note: "Il colore dei pulsanti e dei collegamenti in tutta l’app.") {
                    AppTintPicker(look: $look, layout: .grid(columns: 6))
                }
                inspectorGroup("Barra su iPhone", note: "Su iPad e Mac le sezioni stanno nella barra laterale.") {
                    AppBarPicker(look: $look)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .onChange(of: look.app.iconStyle) { appView = .home }
        .onChange(of: look.app.icon) { appView = .home }
        .onChange(of: look.app.special) { appView = .home }
        .onChange(of: homeLook) { appView = .home }
        .onChange(of: look.app.tabBar) {
            appView = .today
            device = .phone
        }
    }

    /// One group of the inspector: its name, its controls, a line under them.
    private func inspectorGroup<Content: View>(_ title: LocalizedStringKey, note: LocalizedStringKey?,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The selected sticker

    /// Whether the stickers' tool is what is open: Saluto, on Accessorio, with stickers beside the date.
    private var stickerToolOpen: Bool {
        let open = isWide ? widePart : part
        // The inspector shows every tool of the part at once.
        let beside = isWide || tool(of: .greeting) == .beside
        return open == .greeting && beside && look.accessory == .stickers && !arranging
    }

    /// The selected sticker from a keyboard: the arrows move it, + and −
    /// size it, R turns it, ⌫ removes it and ⌘D copies it. Invisible
    /// buttons, there only while a sticker is selected.
    @ViewBuilder
    private var stickerKeys: some View {
        // Letters and arrows belong to a text field while one is being typed in.
        if let id = selectedSticker, !nameFocused, !typingInTools, mode != .greeting, mode != .besideText {
            Group {
                Button("Sposta a sinistra") { nudge(id, x: -0.04) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Sposta a destra") { nudge(id, x: 0.04) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Sposta su") { nudge(id, y: -0.04) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Sposta giù") { nudge(id, y: 0.04) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button(StickerEdit.bigger.title) { editSticker(id, .bigger) }
                    .keyboardShortcut("+", modifiers: [])
                // + without Shift, on most keyboards.
                Button(StickerEdit.bigger.title) { editSticker(id, .bigger) }
                    .keyboardShortcut("=", modifiers: [])
                Button(StickerEdit.smaller.title) { editSticker(id, .smaller) }
                    .keyboardShortcut("-", modifiers: [])
                Button(StickerEdit.turn.title) { editSticker(id, .turn) }
                    .keyboardShortcut("r", modifiers: [])
                Button(StickerEdit.remove.title) { editSticker(id, .remove) }
                    .keyboardShortcut(.delete, modifiers: [])
                Button(StickerEdit.duplicate.title) { editSticker(id, .duplicate) }
                    .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Moves a sticker by a fraction of its panel.
    private func nudge(_ id: UUID, x: Double = 0, y: Double = 0) {
        withAnimation(.snappy) {
            look.updateSticker(id) {
                $0.x += x
                $0.y += y
            }
        }
    }

    /// Does one of a sticker's actions, and selects what comes after it.
    private func editSticker(_ id: UUID, _ edit: StickerEdit) {
        withAnimation(.snappy) { selectedSticker = look.edit(sticker: id, edit) }
    }

    // MARK: - Top bar

    /// Arranging the sections on the page: the task's name and Fine.
    private var arrangingBar: some View {
        HStack {
            Spacer()
            Text("Disponi").font(.headline)
            Spacer()
            Button("Fine") { arranging = false }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("customize-arrange-done")
        }
    }

    /// Leaves, asking first if anything changed.
    private func askCancel() {
        if look == original { leave(then: cancel) } else { confirmingCancel = true }
    }

    /// The undo and redo capsule.
    private var undoRedo: some View {
        UndoRedoCapsule(canUndo: history.canUndo, canRedo: history.canRedo, undo: undo, redo: redo)
    }

    /// ✓: keeps the draft.
    private var doneButton: some View {
        Button { leave(then: done) } label: {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(isNew ? Text("Aggiungi") : Text("Fine"))
        .accessibilityIdentifier("customize-edit-done")
    }

    /// The iPhone's bar: ✕ and undo and redo on the left, ••• and ✓ on the right.
    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 8) {
            if arranging {
                arrangingBar
            } else {
                roundButton("Annulla", symbol: "xmark", id: "customize-editor-cancel", shortcut: .cancelAction, action: askCancel)
                undoRedo
                Spacer()
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Altre azioni")
                .accessibilityIdentifier("customize-editor-more")
                doneButton
            }
        }
        .frame(height: 48)
    }

    /// The iPad's bar: ✕ and undo and redo on the left, the look's name in
    /// the middle, ✓ on the right. The name is set in Tema.
    private var padBar: some View {
        ZStack {
            if arranging {
                arrangingBar
            } else {
                Group {
                    if look.name.isEmpty { Text("Senza nome") } else { Text(verbatim: look.name) }
                }
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: 360)
                HStack(spacing: 8) {
                    roundButton("Annulla", symbol: "xmark", id: "customize-editor-cancel", shortcut: .cancelAction, action: askCancel)
                    undoRedo
                    Spacer()
                    doneButton
                }
            }
        }
        .frame(height: 48)
    }

    /// A Mac's toolbar: the name to type in and whether it has changed on the
    /// left; undo and redo, Annulla and Fine on the right.
    private var macBar: some View {
        HStack(spacing: 12) {
            if arranging {
                arrangingBar
            } else {
                nameField
                    .frame(width: 240)
                (look == original ? Text("Flavor") : Text("Modificato"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                undoRedo
                Button("Annulla", action: askCancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("customize-editor-cancel")
                Button { leave(then: done) } label: { isNew ? Text("Aggiungi") : Text("Fine") }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("customize-edit-done")
            }
        }
        .frame(height: 48)
    }

    /// The look's name, typed in place.
    private var nameField: some View {
        TextField("Il mio Flavor", text: Binding { look.name } set: { look.name = String($0.prefix(TodayStyle.nameLimit)) })
            .font(.headline)
            .submitLabel(.done)
            .focused($nameFocused)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Color(white: 0.11), in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(Text("Nome del Flavor"))
            .accessibilityIdentifier("customize-name-field")
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

    /// The look itself: its name, starting over, deleting it. System menu
    /// items drop accessibility identifiers, so tests find these by their labels.
    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button("Rinomina", systemImage: "pencil", action: rename)
            Button("Ripristina tutto", systemImage: "arrow.uturn.backward") {
                withAnimation(.snappy) { look = original }
            }
            .disabled(look == original)
        }
        if delete != nil {
            Button("Elimina Flavor…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
    }

    /// Goes to the overview with the cursor in the name.
    private func rename() {
        withAnimation(.snappy) { part = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            nameFocused = true
        }
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
    ///   - home: For App, the Home Screen or Dock drawn in the page's place.
    ///   - zoomed: During a task: the page nearly as wide as the screen, its top in view.
    ///   - skip: Zoomed, how much of the page's top, at full size, to scroll past.
    private func page(on target: Screen, screen: CGSize, home: AppPreview.Mode? = nil, zoomed: Bool = false,
                      skip: CGFloat = 0) -> some View {
        Color.clear
            .overlay {
                GeometryReader { room in
                    let size = target.size
                    let fit = zoomed
                        ? room.size.width * 0.92 / size.width
                        : min(room.size.height / size.height, room.size.width / size.width)
                    // Before arriving and after leaving, the page is on the gallery's
                    // card, where the look was; without a card, it covers the screen.
                    let frame = room.frame(in: .named(Self.space))
                    let away = origin ?? CGRect(origin: .zero, size: screen)
                    let cover = origin.map { $0.width / size.width }
                        ?? max(screen.width / size.width, screen.height / size.height)
                    let toScreen = CGSize(width: away.midX - frame.midX, height: away.midY - frame.midY)
                    // The card's corners, as ``LookScreen`` draws them before scaling.
                    let awayRadius: CGFloat = origin == nil ? 0 : 48
                    Group {
                        if let home {
                            AppPreview(look: look, mode: home, homeLook: homeLook, screen: target.size, insets: target.insets)
                                .transition(.opacity)
                        } else {
                            livePage(on: target)
                                .transition(.opacity)
                        }
                    }
                    // Handles on the page stay a finger's size however small it is drawn.
                    .environment(\.previewScale, arrived ? fit : cover)
                    .environment(\.stickerMenu, mode == .stickers)
                    .clipShape(.rect(cornerRadius: arrived ? target.cornerRadius : awayRadius, style: .continuous))
                    // Zoomed, the page hangs from the top of the room, its header in view.
                    .scaleEffect(arrived ? fit : cover, anchor: zoomed ? .top : .center)
                    .frame(width: room.size.width, height: room.size.height, alignment: zoomed ? .top : .center)
                    .offset(y: zoomed ? -skip * fit : 0)
                    .offset(arrived ? .zero : toScreen)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                }
                // Zoomed, what hangs below the room is cut off; otherwise the page
                // is free to cover the screen as it settles.
                .mask { Rectangle().padding(zoomed ? 0 : -4000) }
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
            TodayLanding(day: shell.day, draft: $look, arranging: arranging, quiet: true, selection: $selectedSticker,
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
                .onTapGesture { part = .special }
                .accessibilityLabel(Text("Regola il Flavor"))
                .accessibilityAddTraits(.isButton)
        }
        .transition(.opacity)
    }

    // MARK: - Under the page

    /// The overview, or the open part's tools and the capsule.
    @ViewBuilder
    private func lower(screen: CGSize) -> some View {
        // One height for the overview and every part, so the page keeps its
        // size while the student moves between them.
        let height = min(390, screen.height * Self.lowerShare)
        Group {
            if let part {
                VStack(spacing: 10) {
                    partTools(part)
                        .frame(maxHeight: .infinity)
                    switcher(part)
                        .padding(.horizontal, 16)
                }
            } else {
                // On a small phone the cards scroll rather than squeeze the page.
                ScrollView {
                    overview
                        .padding(.horizontal, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .frame(height: height)
        .padding(.bottom, insets.bottom + 4)
    }

    /// Every part at once: the look's name, then a card for each part.
    private var overview: some View {
        VStack(spacing: 12) {
            nameField

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

    /// The open part's tools under the page: a tab for each, then the one chosen.
    @ViewBuilder
    private func partTools(_ part: LookPart) -> some View {
        let current = tool(of: part)
        VStack(spacing: 8) {
            if part.tools.count > 1 {
                GlassSegmentedPicker("Strumenti", selection: toolBinding(part), options: part.tools) { tool in
                    Text(tool.title)
                }
                .padding(.horizontal, 16)
                .accessibilityIdentifier("customize-tools")
            }
            Group {
                if current == .special {
                    SpecialFlavorControls(style: $look, preview: $preview.animation(.snappy),
                                          duplicateAsClassic: duplicateAsClassic)
                        .scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        toolView(current, layout: .strip)
                            .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .id(current)
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        }
    }

    /// One tool's controls.
    private func toolView(_ tool: LookTool, layout: ToolLayout) -> some View {
        LookToolView(tool: tool, look: $look, layout: layout, selectedSticker: $selectedSticker,
                     homeLook: $homeLook, arranging: $arranging, pickStickers: { sheet = .stickerPicker },
                     enterMode: layout == .strip ? { enter($0) } : nil, typing: $typingInTools)
    }

    /// The tool a part shows: the one last chosen there, or its first.
    private func tool(of part: LookPart) -> LookTool {
        tools[part] ?? part.tools.first ?? .classics
    }

    /// The tabs' selection for a part.
    private func toolBinding(_ part: LookPart) -> Binding<LookTool> {
        Binding { tool(of: part) } set: { tools[part] = $0 }
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

            PartCapsule(parts: LookPart.parts(for: look), current: current, pick: show) {
                withAnimation(.snappy) { part = nil }
            }

            roundButton("Tutte le parti", symbol: "square.grid.2x2", id: "customize-parts") {
                part = nil
            }
        }
    }

    // MARK: - Opening

    /// Opens a part's tools.
    private func show(_ next: LookPart) {
        part = next
    }

    /// Opens what a tap on the page means: its part's tools, or a section's card.
    private func open(_ zone: TodayLanding.Zone) {
        // During a task the page only selects stickers: nothing else opens.
        guard mode == nil else { return }
        // A sticker tapped on the iPhone starts the stickers' task, with it selected.
        if zone == .stickers, selectedSticker != nil, !isWide, look.special == nil {
            enter(.stickers)
            return
        }
        if let opening = LookPart.opening(zone, in: look) {
            tools[opening.part] = opening.tool
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

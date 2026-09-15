import SwiftUI

/// Personalizza, opened from Oggi's bar. It opens as a gallery of saved
/// styles, paged like the Lock Screen's: swipe between them at a reduced size,
/// Personalizza to edit the one in the middle, + to add a new one, ✓ to use
/// it, and hold a card to delete it. Editing shows the page at full size with
/// its zones outlined.
///
/// One commit point per action, kept by ``LookLibrary``: the editor's Fine
/// saves the style, ✓ makes it the page's. Saving the style in use shows at
/// once, since it is the page's already.
///
/// Laid over the app by ``NewRootView``. Like the Lock Screen, the look in use
/// starts covering the screen, exactly where the app is, and shrinks into the
/// middle card while the rest of the gallery fades in; closing grows the
/// middle card back over the app before the gallery goes.
struct CustomizeOggi: View {
    @Environment(\.shell) private var shell
    @Environment(Session.self) private var session
    @Environment(AgendaService.self) private var agenda
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var active = TodayStyle()
    @AppStorage(TodayStyle.libraryKey) private var storedLibrary = ""
    @AppStorage(TodayStyle.selectionKey) private var storedSelection = 0

    @State private var library: LookLibrary
    @State private var page: Int?
    /// The card whose deletion is being confirmed.
    @State private var deleting: Int?
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
        let library = LookLibrary(looks: looks, selection: defaults.integer(forKey: TodayStyle.selectionKey))
        _library = State(initialValue: library)
        _page = State(initialValue: library.selection)
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
        .confirmationDialog("Eliminare questo stile?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina stile", role: .destructive) {
                if let deleting { delete(deleting) }
            }
            .accessibilityIdentifier("customize-delete-confirm")
        } message: {
            Text("Non si può annullare.")
        }
    }

    // MARK: - Gallery

    private func carousel(screen: CGSize, insets: EdgeInsets) -> some View {
        let cardSize = CGSize(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
        return ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(library.looks.enumerated()), id: \.offset) { index, look in
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
                            .contextMenu {
                                if library.canRemove {
                                    Button("Elimina stile", systemImage: "trash", role: .destructive) { deleting = index }
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Stile \(index + 1)"))
                            .accessibilityValue(index == library.selection ? Text("In uso") : Text(""))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityActions {
                                if library.canRemove {
                                    Button("Elimina stile") { deleting = index }
                                }
                            }
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
            // The position's first value is not applied to a lazy stack: without
            // this the carousel opened on the first look while the look in use,
            // off to the side, was the one shrinking out of the app.
            .onAppear { reader.scrollTo(page, anchor: .center) }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                // Saved styles stay saved: closing only leaves the page on the
                // style it already uses.
                Button("Chiudi", role: .close) { close() }
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
                    ForEach(library.looks.indices, id: \.self) { index in
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

                    Button("Nuovo stile", systemImage: "plus", action: addLook)
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
        guard library.looks.indices.contains(index) else { return }
        editing = EditedLook(index: index, look: library.looks[index])
    }

    /// Adds a blank style at the end, brings it to the middle, and opens it
    /// once it is there, so the editor zooms out of its card.
    private func addLook() {
        library.append(TodayStyle())
        let index = library.looks.count - 1
        unsavedLook = index
        withAnimation(.snappy) { page = index } completion: {
            beginEditing(index)
        }
    }

    /// Saves the style without choosing it: ✓ does that. The style in use is
    /// the page's already, so the page shows the change.
    private func save(_ look: TodayStyle, at index: Int) {
        library.save(look, at: index)
        if index == library.selection { active = library.active }
        unsavedLook = nil
        page = index
        editing = nil
        persist()
    }

    /// A style added with + and then cancelled goes, once the editor has
    /// zoomed back into its card.
    private func dropCancelledLook() {
        guard let index = unsavedLook else { return }
        unsavedLook = nil
        withAnimation(.snappy) {
            page = library.selection
        } completion: {
            library.remove(at: index)
        }
    }

    private func use(_ index: Int) {
        library.use(index)
        active = library.active
        persist()
    }

    /// Deleting the style in use hands the page to its neighbour.
    private func delete(_ index: Int) {
        guard library.remove(at: index) else { return }
        active = library.active
        // The cards are keyed by position: the one in the middle stays there
        // only if the page moves back with it.
        let middle = page ?? 0
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

    /// Grows the middle card back over the app, then goes. The carousel first
    /// returns to the style in use, which is what the app shows.
    private func close() {
        withAnimation(Self.expand) {
            page = library.selection
            expanded = true
        } completion: {
            shell.isCustomizing = false
        }
    }
}

/// One style at full size with its zones outlined, over the bento panel.
/// Tapping a zone opens its page in the panel; holding the page, or Disponi,
/// arranges it. Nothing reaches the style until Fine, and Annulla asks before
/// throwing changes away.
private struct LookEditor: View {
    let original: TodayStyle
    let onSave: (TodayStyle) -> Void

    @Environment(\.shell) private var shell
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var draft: TodayStyle
    @State private var panelPath: [CustomizePage] = []
    @State private var arranging = false
    @State private var panelDetent = BentoPanel.small
    @State private var confirmingDiscard = false

    init(look: TodayStyle, onSave: @escaping (TodayStyle) -> Void) {
        original = look
        self.onSave = onSave
        _draft = State(initialValue: look)
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, draft: $draft, arranging: arranging,
                             onAddSticker: { panelPath = [.accessory] }) { zone in
                    // Holding a zone arranges the page; the tap that ends the
                    // hold must not also open the zone.
                    guard !arranging else { return }
                    panelPath = [CustomizePage(zone: zone)]
                    panelDetent = BentoPanel.small
                }
                .padding(.top, 8)
                .padding(.bottom, 420)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    guard !arranging else { return }
                    withAnimation(.snappy) { arranging = true }
                })
            }
            // The look's own page, as on the card it zooms out of.
            .background(TodayBackgroundView(style: draft).ignoresSafeArea())
            .sensoryFeedback(.impact(weight: .medium), trigger: arranging) { _, new in new }
            .navigationTitle(arranging ? "Disponi" : "Personalizza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // Buttons in the look's colour, as the app will draw them.
            .tint(draft.controlTint(scheme))
            .preferredColorScheme(draft.appearance.colorScheme)
            // The panel stays while editing and steps away while arranging.
            .sheet(isPresented: Binding(get: { !arranging }, set: { _ in })) {
                BentoPanel(style: $draft, path: $panelPath, arranging: $arranging, detent: $panelDetent)
                    // Asked from the panel, the one on top: the editor under it
                    // cannot present while the panel is up.
                    .confirmationDialog("Scartare le modifiche?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Scarta modifiche", role: .destructive) { dismiss() }
                            .accessibilityIdentifier("customize-editor-discard")
                        Button("Continua a modificare", role: .cancel) {}
                    }
                    .presentationDetents([BentoPanel.small, .large], selection: $panelDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: BentoPanel.small))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // While arranging, the only way on is Fine, back to editing.
        if !arranging {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla", role: .cancel) {
                    if hasChanges { confirmingDiscard = true } else { dismiss() }
                }
                .accessibilityIdentifier("customize-editor-cancel")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if arranging {
                // Arranging is a step inside editing: Fine returns to it.
                Button("Fine", systemImage: "checkmark") { withAnimation(.snappy) { arranging = false } }
                    .accessibilityIdentifier("customize-arrange-done")
            } else {
                Button("Fine", systemImage: "checkmark") { onSave(draft) }
                    .accessibilityIdentifier("customize-editor-done")
            }
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

import SwiftUI

/// Personalizza, opened from Oggi's bar: the student's looks, the way the Lock
/// Screen keeps its wallpapers.
///
/// **The gallery.** The saved looks are cards on black, the last one an empty
/// card to add another. The look in the middle is the look the app uses —
/// swiping is choosing, and every look stays saved, so swiping back undoes it.
/// Tapping the middle card goes back to the app wearing it. Pulling a card up
/// lifts it off the gallery and shows the trash under it; the delete is
/// immediate, with Annulla offered for a few seconds. With one look left the
/// card only stretches: the page always needs one.
///
/// **Editing.** Personalizza grows the middle card to full size and hands it to
/// ``LookEditor``, which works on a draft: Fine keeps it, Annulla drops it.
///
/// **Adding.** The + button, or the empty card, opens ``NewLookGallery``;
/// picking a starting point opens the editor on it, and Aggiungi asks once what
/// the app should wear with it (``AppPairQuestion``): pair it with the page, or
/// dress it in ``AppLookEditor``. Either way the new look goes in use.
///
/// Laid over the app by ``RootView``. The look in use starts covering the
/// screen, exactly where the app is, and shrinks into the middle card while
/// the gallery fades in; closing grows it back over the app before the gallery
/// goes, and puts the look's icon on the Home Screen.
struct CustomizeOggi: View {
    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var active = TodayStyle()
    @AppStorage(TodayStyle.libraryKey) private var storedLibrary = ""
    @AppStorage(TodayStyle.selectionKey) private var storedSelection = 0

    /// The saved looks and which one the page uses.
    @State private var library: LookLibrary
    /// The card in the middle of the carousel, or `nil` to follow the library's
    /// selection. One past the last look is the empty card.
    @State private var page: Int?
    /// The middle card covers the screen, on opening and on closing.
    @State private var expanded = true
    /// The middle card covers the screen for editing.
    @State private var filling = false
    /// How far the middle card has been pulled up; negative is up.
    @State private var lift: CGFloat = 0
    /// The middle card rests lifted, with the trash showing.
    @State private var lifted = false
    /// The card on its way out after the trash is tapped.
    @State private var removing: Int?
    /// After a delete, the first card that moved into the gap: it and the cards
    /// after it start a place to the right and slide in, so the row closes up.
    @State private var closing: Int?
    /// The look just deleted, while Annulla can still bring it back.
    @State private var removed: RemovedLook?
    /// The look being edited, if any.
    @State private var edit: LookEdit?
    @State private var addingLook = false
    /// The question at the end of adding is up.
    @State private var askingApp = false
    /// Where the app half's editor was opened from, while it is open.
    @State private var appEditor: AppEditorOrigin?
    /// The app half as it was when its editor opened, for its Annulla.
    @State private var appBefore = AppLook()

    /// How much smaller than the screen a card is.
    static let cardScale: CGFloat = 0.68
    /// The curve a card grows to cover the screen on, and shrinks back.
    private static let expand = Animation.spring(duration: 0.45, bounce: 0.1)
    /// How far above its place a lifted card rests.
    private static let liftStop: CGFloat = 150

    /// Reads the saved looks before the first layout, so the carousel opens on the one in use.
    init() {
        // Read before the first layout, so the carousel starts on the look in
        // use instead of scrolling to it while it shrinks.
        let defaults = UserDefaults.standard
        let looks = TodayStyle.library(from: defaults.string(forKey: TodayStyle.libraryKey) ?? "", active: TodayStyle())
        let library = LookLibrary(looks: looks, selection: defaults.integer(forKey: TodayStyle.selectionKey))
        _library = State(initialValue: library)
        _page = State(initialValue: library.selection)
    }

    /// Which card is in the middle: the one scrolled to, else the one in use.
    private var middle: Int { page ?? library.selection }

    /// The middle card is the empty one that adds a look.
    private var onNewCard: Bool { middle >= library.looks.count }

    /// Full size: covering the screen on the way in and out, and for editing.
    private var filled: Bool { expanded || filling }

    /// The draft the editors change.
    private var draft: Binding<TodayStyle> {
        Binding { edit?.draft ?? library.active } set: { edit?.draft = $0 }
    }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            // The cards stand for the whole screen, status bar and home
            // indicator included, so they are measured without the safe area.
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            let card = CGSize(width: screen.width * Self.cardScale, height: screen.height * Self.cardScale)
            ZStack {
                Color.black
                    .opacity(expanded ? 0 : 1)
                carousel(screen: screen, insets: insets, card: card)
                chrome(screen: screen, insets: insets, card: card)
                    .opacity(filled || edit != nil ? 0 : 1)
                    .allowsHitTesting(!filled && edit == nil)
                if let edit {
                    LookEditor(look: draft, original: edit.original, isNew: edit.index == nil, insets: insets,
                               cancel: cancelEditing, done: finishEditing, openApp: openAppFromMenu)
                        .transition(edit.index == nil ? .move(edge: .bottom) : .identity)
                        .zIndex(2)
                }
                if appEditor != nil {
                    AppLookEditor(look: draft, screen: screen, insets: insets, cancel: cancelApp, done: finishApp)
                        .transition(.move(edge: .bottom))
                        .zIndex(3)
                }
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
        .sheet(isPresented: $addingLook) {
            NewLookGallery(current: library.active, pick: startAdding)
        }
        .sheet(isPresented: $askingApp) {
            AppPairQuestion(look: draft.wrappedValue, pair: pairAndAdd, customise: customiseApp)
                .presentationDetents([.height(500)])
                .interactiveDismissDisabled()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
    }

    // MARK: - Gallery

    /// The looks as cards to scroll through, then the empty card, the middle
    /// one snapping into place.
    private func carousel(screen: CGSize, insets: EdgeInsets, card: CGSize) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(0...library.looks.count, id: \.self) { index in
                        let isMiddle = index == middle
                        slot(index, screen: screen, insets: insets)
                            .frame(width: card.width, height: card.height)
                            .scrollTransition(.interactive, axis: .horizontal) { [filled] view, phase in
                                // Off while covering the screen, where it would let
                                // the app show through.
                                view
                                    .scaleEffect(phase.isIdentity || filled ? 1 : 0.92)
                                    .opacity(phase.isIdentity || filled ? 1 : 0.6)
                            }
                            // A deleted card is pushed off through the top of the
                            // screen, whole, the way it was being pulled — not
                            // shrunk away in place.
                            .offset(y: isMiddle ? (removing == index ? -screen.height : lift) : 0)
                            .offset(x: (closing.map { index >= $0 } ?? false) ? card.width + 18 : 0)
                            .modifier(FillScreen(progress: isMiddle && filled ? 1 : 0, screen: screen))
                            .opacity(isMiddle || !filled ? 1 : 0)
                            .zIndex(isMiddle ? 1 : 0)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // So a card pushed off the top leaves the screen rather than the
            // scroll view.
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page, anchor: .center)
            .scrollDisabled(filled || edit != nil)
            .contentMargins(.horizontal, (screen.width - card.width) / 2, for: .scrollContent)
            // The position's first value is not applied to a lazy stack: without
            // this the carousel opened on the first look while the look in use,
            // off to the side, was the one shrinking out of the app.
            .onAppear { reader.scrollTo(page, anchor: .center) }
            // Swiping is choosing: the app takes the look that comes to rest in
            // the middle. Every look stays saved, so swiping back undoes it.
            .onChange(of: page) { _, page in
                if lift != 0 { withAnimation(.snappy) { drop() } }
                guard edit == nil, let page, page < library.looks.count else { return }
                use(page)
            }
        }
    }

    /// One place in the carousel: a look, or the empty card that adds one.
    @ViewBuilder
    private func slot(_ index: Int, screen: CGSize, insets: EdgeInsets) -> some View {
        if index < library.looks.count {
            let look = library.looks[index]
            LookScreen(look: look, scale: Self.cardScale, screen: screen, insets: insets)
                // A card whose look changes — its neighbour sliding into its
                // place after a delete — is a new card, not the page animating
                // from one look into the other.
                .id(look.rawValue)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                .contentShape(.rect(cornerRadius: 48 * Self.cardScale))
                .onTapGesture { tap(index) }
                .gesture(liftGesture(for: index))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(look.displayName(at: index)))
                .accessibilityValue(Text("\(index + 1) di \(library.looks.count)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(index == middle ? Text("Tocca per tornare all'app") : Text("Tocca per usarlo"))
                .accessibilityAction(named: "Personalizza") { if index == middle { beginEditing() } }
                .accessibilityAction(named: "Elimina Flavor") {
                    if index == middle, library.canRemove { delete(index) }
                }
                .accessibilityIdentifier("customize-card-\(index)")
        } else {
            NewLookCard()
                .contentShape(.rect(cornerRadius: 48 * Self.cardScale))
                .onTapGesture { tap(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Nuovo Flavor")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("customize-card-new")
        }
    }

    /// Pulling the middle card up lifts it and shows the trash; pulling down,
    /// or not far enough, sets it back. Sideways is the carousel's: the pan
    /// only begins when it starts vertical, so the scroll view keeps every
    /// horizontal swipe. A SwiftUI drag on the card took them all instead.
    private func liftGesture(for index: Int) -> VerticalPan {
        VerticalPan { translation in
            guard index == middle, edit == nil else { return }
            let start: CGFloat = lifted ? -Self.liftStop : 0
            var y = start + translation
            if y > 0 {
                y /= 4
            } else if !library.canRemove {
                // The last look only stretches: there is no trash to show.
                y = -pow(-y, 0.6)
            } else if y < -Self.liftStop {
                y = -Self.liftStop - pow(-y - Self.liftStop, 0.7)
            }
            lift = y
        } ended: { velocity in
            guard index == middle, edit == nil else { return }
            let up = (lift < -70 || velocity < -600) && velocity < 600
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                lifted = library.canRemove && up
                lift = lifted ? -Self.liftStop : 0
            }
        }
    }

    // MARK: - Chrome

    /// Everything around the cards: the name above, the trash and Annulla,
    /// and the dots and buttons below.
    private func chrome(screen: CGSize, insets: EdgeInsets, card: CGSize) -> some View {
        let cardTop = (screen.height - card.height) / 2
        let cardBottom = cardTop + card.height
        let reveal = library.canRemove && !onNewCard ? min(max(-lift / 130, 0), 1) : 0
        return ZStack(alignment: .top) {
            Group {
                if let removed {
                    undoToast(removed)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    VStack(spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .tracking(1.2)
                        Text(subtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(lift < 0 ? 0 : 1)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            // Padding, not an offset: an offset moves what is drawn but not
            // where VoiceOver and a test find it.
            .padding(.top, cardTop - 52)

            Button("Elimina Flavor", systemImage: "trash", role: .destructive) { delete(middle) }
                .labelStyle(.iconOnly)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.red)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.red.opacity(0.3)).interactive(), in: .circle)
                .scaleEffect(0.6 + 0.4 * reveal)
                .opacity(reveal)
                .padding(.top, cardBottom - Self.liftStop + 50 + (Self.liftStop + lift) * 0.35)
                .allowsHitTesting(lifted)
                .accessibilityHidden(!lifted)
                .accessibilityIdentifier("customize-trash")

            browseControls
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, insets.bottom + 4)
                .opacity(1 - min(max(-lift / 90, 0), 1))
        }
        .environment(\.colorScheme, .dark)
        // The system's own type and white, whatever the look in use sets on the app.
        .fontDesign(.default)
        .tint(.white)
        .animation(.snappy, value: removed)
    }

    /// The name of the card in the middle.
    private var title: String {
        onNewCard ? String(localized: "Nuovo Flavor").uppercased()
            : library.looks[middle].displayName(at: middle).uppercased()
    }

    /// What the app wears with the card in the middle.
    private var subtitle: LocalizedStringKey {
        onNewCard ? "Speciale, classico, da un colore o da una foto"
            : library.looks[middle].special != nil ? "Speciale · cambia tutta l’app"
            : library.looks[middle].app.paired ? "App abbinata" : "App su misura"
    }

    /// Flavor eliminato, with the way back, for a few seconds.
    private func undoToast(_ removed: RemovedLook) -> some View {
        HStack(spacing: 12) {
            Text("Flavor eliminato")
                .font(.subheadline.weight(.semibold))
            Button("Annulla") { undoDelete() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier("customize-undo")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .task(id: removed.id) {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) { self.removed = nil }
            // Past the way back: the deleted look's sticker images can go.
            persist(pruning: true)
        }
    }

    /// The controls under the carousel: the page dots, and the ways to edit or add a look.
    private var browseControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(library.looks.indices, id: \.self) { index in
                    Circle()
                        .fill(index == middle ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 7, height: 7)
                }
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(onNewCard ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
            .animation(.snappy, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Flavor \(min(middle + 1, library.looks.count)) di \(library.looks.count)"))

            HStack(spacing: 12) {
                Button { beginEditing() } label: {
                    Text("Personalizza")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .disabled(onNewCard)
                .accessibilityIdentifier("customize-edit")

                // The same 44-point label as Personalizza inside the same
                // glass style, so the two come out the same height.
                Button { addingLook = true } label: {
                    Label("Nuovo Flavor", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("customize-add")
            }
            .padding(.horizontal, 60)
        }
        // White on black, as the Lock Screen's gallery: the look's tint belongs to the cards.
        .tint(.white)
        .foregroundStyle(.white)
    }

    // MARK: - Browsing

    /// The middle card goes back to the app, or adds a look if it is the empty
    /// one; a card to the side comes to the middle; a lifted card is set back.
    private func tap(_ index: Int) {
        if lifted {
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { drop() }
        } else if index != middle {
            withAnimation(.snappy) { page = index }
        } else if index >= library.looks.count {
            addingLook = true
        } else {
            close()
        }
    }

    /// Sets a lifted card back in its place.
    private func drop() {
        lifted = false
        lift = 0
    }

    /// Makes one look the page's.
    ///
    /// - Parameter index: Which look.
    private func use(_ index: Int) {
        guard index != library.selection, library.looks.indices.contains(index) else { return }
        library.use(index)
        active = library.active
        storedSelection = library.selection
    }

    /// Sends the lifted card away, then deletes it and offers it back. Deleting
    /// the look in use hands the page to its neighbour.
    private func delete(_ index: Int) {
        guard library.canRemove, library.looks.indices.contains(index) else { return }
        let look = library.looks[index], selection = library.selection
        withAnimation(.easeIn(duration: 0.3)) {
            removing = index
        } completion: {
            // Not animated: the slot's offset would bring its new look down
            // from the top where the deleted one went. The cards after it are
            // put a place to the right instead, then slide into the gap.
            guard library.remove(at: index) else { return }
            active = library.active
            removing = nil
            closing = index
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { closing = nil }
            }
            drop()
            // The cards are keyed by position: the one in the middle stays
            // there only if the page moves with it.
            page = min(index, library.looks.count - 1)
            persist()
            withAnimation(.snappy) { removed = RemovedLook(look: look, index: index, selection: selection) }
        }
    }

    /// Puts the deleted look back where it was, in use as it was.
    private func undoDelete() {
        guard let removed else { return }
        library.restore(removed.look, at: removed.index, selection: removed.selection)
        active = library.active
        persist()
        withAnimation(.snappy) {
            self.removed = nil
            page = removed.index
        }
    }

    /// Writes the library and the selection out; past the undo, also drops
    /// sticker images no saved look draws any more.
    private func persist(pruning: Bool = false) {
        storedLibrary = TodayStyle.encodeLibrary(library.looks)
        storedSelection = library.selection
        guard pruning, removed == nil else { return }
        let inUse = library.looks.reduce(into: active.storedImageIDs) { $0.formUnion($1.storedImageIDs) }
        StickerStore.shared.prune(keeping: inUse)
    }

    /// Grows the middle card back over the app, puts its icon on the Home
    /// Screen, then goes. The app is already wearing the middle look.
    private func close() {
        drop()
        removed = nil
        persist(pruning: true)
        let icon = library.active.resolved.appIcon
        withAnimation(Self.expand) {
            expanded = true
        } completion: {
            shell.isCustomizing = false
            Task { await AppIconSwitcher.apply(icon) }
        }
    }

    // MARK: - Editing

    /// Grows the middle card to full size, then hands it to the editor.
    private func beginEditing() {
        guard library.looks.indices.contains(middle) else { return }
        let index = middle, look = library.looks[index]
        drop()
        withAnimation(Self.expand) {
            filling = true
        } completion: {
            edit = LookEdit(draft: look, original: look, index: index)
        }
    }

    /// Opens the editor on a starting point from the add gallery.
    ///
    /// - Parameter look: The look picked.
    private func startAdding(_ look: TodayStyle) {
        addingLook = false
        withAnimation(.spring(duration: 0.5, bounce: 0.08)) {
            edit = LookEdit(draft: look, original: look, index: nil)
        }
    }

    /// Leaves the editor without keeping anything.
    private func cancelEditing() {
        guard let edit else { return }
        if edit.index == nil {
            withAnimation(.spring(duration: 0.45, bounce: 0.05)) { self.edit = nil }
        } else {
            self.edit = nil
            withAnimation(Self.expand) { filling = false }
        }
    }

    /// Keeps the draft: a saved look is written back; a new one asks about the app first.
    private func finishEditing() {
        guard let edit else { return }
        guard let index = edit.index else {
            askingApp = true
            return
        }
        library.save(edit.draft, at: index)
        if index == library.selection { active = library.active }
        persist()
        self.edit = nil
        withAnimation(Self.expand) { filling = false }
    }

    // MARK: - The app half

    /// Pairs the new look's app with its page, and adds it.
    private func pairAndAdd() {
        edit?.draft.pairApp()
        askingApp = false
        addNew()
    }

    /// Opens the app half before adding the new look.
    private func customiseApp() {
        askingApp = false
        appBefore = draft.wrappedValue.app
        withAnimation(.spring(duration: 0.45, bounce: 0.05)) { appEditor = .adding }
    }

    /// Opens the app half of the look being edited, from ••• ▸ App.
    private func openAppFromMenu() {
        appBefore = draft.wrappedValue.app
        withAnimation(.spring(duration: 0.45, bounce: 0.05)) { appEditor = .menu }
    }

    /// Puts the app half back. After adding, the question comes back too.
    private func cancelApp() {
        edit?.draft.app = appBefore
        let origin = appEditor
        withAnimation(.spring(duration: 0.45, bounce: 0.05)) { appEditor = nil }
        if origin == .adding { askingApp = true }
    }

    /// Keeps the app half: after adding, that adds the look; from the menu it
    /// returns to the editor, whose Fine saves it with the rest.
    private func finishApp() {
        let origin = appEditor
        withAnimation(.spring(duration: 0.45, bounce: 0.05)) { appEditor = nil }
        if origin == .adding { addNew() }
    }

    /// Adds the new look at the end and puts it in use: the editor slides
    /// away over the gallery, which has it in the middle.
    private func addNew() {
        guard let edit else { return }
        library.append(edit.draft)
        let index = library.looks.count - 1
        library.use(index)
        active = library.active
        persist()
        page = index
        withAnimation(.spring(duration: 0.5, bounce: 0.05)) { self.edit = nil }
    }
}

/// A look being edited: the draft the editor changes, what it started as, and
/// where it goes.
private struct LookEdit: Equatable {
    /// The look as it is being changed.
    var draft: TodayStyle
    /// The look as editing found it.
    let original: TodayStyle
    /// Its place in the library; `nil` for a look being added.
    let index: Int?
}

/// A deleted look, kept while Annulla can bring it back.
private struct RemovedLook: Equatable {
    /// The look.
    let look: TodayStyle
    /// Where it was.
    let index: Int
    /// Which look was in use before it went.
    let selection: Int
    /// Tells two deletes of equal looks apart, so each gets its own countdown.
    let id = UUID()
}

/// Where the app half's editor was opened from.
private enum AppEditorOrigin {
    /// Straight after adding a look, from the question.
    case adding
    /// From the editor's ••• ▸ App.
    case menu
}

/// The last card: nothing yet, and a way to add a look.
private struct NewLookCard: View {
    /// The view's content.
    var body: some View {
        RoundedRectangle(cornerRadius: 48 * CustomizeOggi.cardScale, style: .continuous)
            .fill(Color(white: 0.07))
            .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .light))
                        .frame(width: 58, height: 58)
                        .glassEffect(.regular, in: .circle)
                    Text("Nuovo Flavor")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
    }
}

/// A pan that begins only when it starts more up or down than sideways, so a
/// card in a horizontal scroll view can be pulled up without taking the
/// scroll view's swipes.
struct VerticalPan: UIGestureRecognizerRepresentable {
    /// How far the finger has moved down; negative is up.
    let changed: (CGFloat) -> Void
    /// The vertical speed the finger left at, in points per second.
    let ended: (CGFloat) -> Void

    /// The delegate that decides whether the pan begins.
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    /// A pan recogniser, with the coordinator as its delegate.
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    /// Reports the pan's movement and its end.
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            changed(recognizer.translation(in: recognizer.view).y)
        case .ended, .cancelled, .failed:
            ended(recognizer.velocity(in: recognizer.view).y)
        default:
            break
        }
    }

    /// Lets the pan begin only when it starts vertical.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Whether the pan begins: only more up or down than sideways.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}

/// Scales a card about its centre until it covers the screen. A transform, not
/// a new frame: the card's content keeps its layout all the way.
private struct FillScreen: GeometryEffect {
    /// 0 at card size, 1 covering the screen.
    var progress: CGFloat
    /// The screen the card grows to cover.
    let screen: CGSize

    /// ``progress``, which the animation drives.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The transform that scales the card about its centre.
    ///
    /// - Parameter size: The card's own size.
    /// - Returns: The transform.
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

#Preview("Nuovo Flavor") {
    NewLookGallery(current: TodayStyle.presets[3]) { _ in }
        .previewEnvironment()
}

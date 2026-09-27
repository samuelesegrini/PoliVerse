import SwiftUI

/// The app half of a look, edited the way the Home Screen is next to a Lock
/// Screen: the app drawn as a card on black, and three round buttons under it —
/// Icona, Colore, Barra — each showing its choices in a strip. One is always
/// open, Icona first, with the Home Screen drawn above it.
///
/// Choosing anything by hand unpairs the app from the page; Automatica, first
/// among the icons and the colours, pairs it again and drops those choices.
/// Reached once straight after adding a look, and afterwards from the
/// editor's ••• ▸ App.
struct AppLookEditor: View {
    /// The draft whose app half is edited.
    @Binding var look: TodayStyle
    /// The screen, which the preview is a share of.
    let screen: CGSize
    /// The screen's safe area.
    let insets: EdgeInsets
    /// Leaves, putting the app half back.
    let cancel: () -> Void
    /// Keeps the app half.
    let done: () -> Void

    /// The environment's `self`.
    @Environment(\.self) private var environment
    /// The choice whose strip is open.
    @State private var option = Option.icon

    /// The three buttons under the preview.
    enum Option: String, CaseIterable, Identifiable {
        /// The Home Screen icon.
        case icon
        /// The app's colour.
        case tint
        /// The tab bar's behaviour.
        case bar

        /// The option's identity, which is its raw value.
        var id: String { rawValue }

        /// What the button is called.
        var title: LocalizedStringKey {
            switch self {
            case .icon: "Icona"
            case .tint: "Colore"
            case .bar: "Barra"
            }
        }
    }

    /// How much smaller than the screen the preview is: as large as the room
    /// between the top bar and the buttons allows.
    private var scale: CGFloat {
        min(0.62, (screen.height - insets.top - insets.bottom - 290) / screen.height)
    }

    /// The view's content.
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, insets.top + 4)
                AppPreview(look: look, mode: option == .icon ? .homeScreen : .app,
                           showsMinimizedBar: option == .bar, screen: screen, insets: insets)
                    .overlay {
                        RoundedRectangle(cornerRadius: 48)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                    }
                    .screenScaled(scale, size: screen)
                    .padding(.top, 14)
                    .animation(.snappy, value: option)
                    .accessibilityIdentifier("app-preview")
                Spacer(minLength: 0)
                strip(option)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(option)
                buttons
                    .padding(.bottom, insets.bottom + 10)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.snappy, value: option)
        .sensoryFeedback(.selection, trigger: look.app)
    }

    /// Annulla, the title, and Fine.
    private var topBar: some View {
        HStack {
            Button("Annulla", action: cancel)
                .buttonStyle(.glass)
                .tint(.white)
                .accessibilityIdentifier("app-cancel")
            Spacer()
            Text("App").font(.headline)
            Spacer()
            Button("Fine", action: done)
                .buttonStyle(.glassProminent)
                .tint(look.resolved.controlTint(.dark))
                .accessibilityIdentifier("app-done")
        }
    }

    // MARK: - Buttons

    /// The three round buttons, the one whose strip is open lit.
    private var buttons: some View {
        HStack(spacing: 18) {
            ForEach(Option.allCases) { option in
                let on = self.option == option
                Button { self.option = option } label: {
                    VStack(spacing: 6) {
                        glyph(option)
                            .frame(width: 56, height: 56)
                            .foregroundStyle(on ? .black : .white)
                            .background(on ? Color.white : Color.clear, in: .circle)
                            .glassEffect(.regular.interactive(), in: .circle)
                        Text(option.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("app-option-\(option.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// What each round button shows: the icon itself, the colour, the bar.
    @ViewBuilder
    private func glyph(_ option: Option) -> some View {
        switch option {
        case .tint:
            Circle()
                .fill(look.resolved.controlTint(.dark))
                .frame(width: 24, height: 24)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
        case .icon:
            Image(look.resolved.appIconPreview)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
        case .bar:
            Image(systemName: "dock.rectangle")
                .font(.title3.weight(.semibold))
        }
    }

    // MARK: - Strips

    /// One button's choices, on glass above the buttons.
    @ViewBuilder
    private func strip(_ option: Option) -> some View {
        Group {
            switch option {
            case .tint:
                tintStrip
            case .icon:
                iconStrip
            case .bar:
                VStack(spacing: 8) {
                    GlassSegmentedPicker("Barra", selection: tabBarBinding) { Text($0.title) }
                        .accessibilityIdentifier("app-tab-bar")
                    Text(look.appTabBar == .minimizes
                         ? "Scorrendo, la barra si riduce alla scheda in cui sei."
                         : "La barra resta intera anche mentre scorri.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    /// Automatico, the swatches, and the system picker for any other colour.
    private var tintStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    automaticTint
                    ColorPicker("Altro colore", selection: tintBinding, supportsOpacity: false)
                        .labelsHidden()
                    ForEach(Flavor.swatches) { swatch in
                        let chosen = !look.app.paired && look.app.tint?.hex == swatch.flavor.hex
                        Button {
                            withAnimation(.snappy) {
                                look.unpairApp()
                                look.app.tint = swatch.flavor
                            }
                        } label: {
                            Circle()
                                .fill(swatch.flavor.base.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if chosen { Circle().strokeBorder(.white, lineWidth: 3).padding(-4) }
                                }
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(swatch.name))
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .accessibilityIdentifier("app-tint-\(swatch.flavor.hex)")
                        .id(swatch.flavor.hex)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if !look.app.paired, let hex = look.app.tint?.hex { reader.scrollTo(hex, anchor: .center) }
            }
        }
    }

    /// The app following the page's colour: the Flavor's own colour, ringed while paired.
    private var automaticTint: some View {
        let paired = look.app.paired
        return Button {
            withAnimation(.snappy) { look.pairApp() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(look.resolved.flavor.base.color)
                    .frame(width: 26, height: 26)
                Text("Automatico")
                    .font(.subheadline.weight(paired ? .semibold : .regular))
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 42)
            .background(.white.opacity(0.08), in: .capsule)
            .overlay {
                if paired { Capsule().strokeBorder(.white, lineWidth: 2.5).padding(-4) }
            }
            .padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("L'app prende colore, icona e barra dal Flavor."))
        .accessibilityAddTraits(paired ? .isSelected : [])
        .accessibilityIdentifier("app-tint-automatic")
    }

    /// The icon's shape, then Automatica and every colour it comes in, or the
    /// special pictures; the one in use ringed.
    private var iconStrip: some View {
        VStack(spacing: 10) {
            GlassSegmentedPicker("Forma", selection: $look.app.iconStyle) { Text($0.title) }
                .accessibilityIdentifier("app-icon-style")
            switch look.appIconStyle {
            case .orbit, .dial, .closeUp: iconColours
            case .special: specialIcons
            }
        }
    }

    /// Automatica, then every colour of the icon in its shape, the one in use
    /// ringed. Automatica is the colour nearest the Flavor, followed as it
    /// changes; the shape alone does not unpair the app.
    private var iconColours: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    automaticIcon
                    ForEach(AppIconChoice.choices(in: look.appIconStyle)) { choice in
                        let chosen = !look.app.paired && look.app.icon == choice
                        Button {
                            withAnimation(.snappy) {
                                look.unpairApp()
                                look.app.icon = choice
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(choice.previewImage(in: look.appIconStyle))
                                    .resizable()
                                    .frame(width: 52, height: 52)
                                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(chosen ? Color.white : .clear, lineWidth: 2.5)
                                            .padding(-4)
                                    }
                                    .padding(4)
                                Text(choice.title)
                                    .font(.caption2)
                                    .foregroundStyle(chosen ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .accessibilityIdentifier("app-icon-\(choice.rawValue)")
                        .id(choice)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            // Opens on the icon in use: Automatica, at the start, while paired.
            .onAppear { if !look.app.paired { reader.scrollTo(look.app.icon, anchor: .center) } }
        }
    }

    /// The icon nearest the Flavor, in the chosen shape: what a paired app wears.
    private var automaticIcon: some View {
        let paired = look.app.paired
        let nearest = AppIconChoice.nearest(to: look.resolved.flavor)
        return Button {
            withAnimation(.snappy) { look.pairApp() }
        } label: {
            VStack(spacing: 5) {
                Image(nearest.previewImage(in: look.appIconStyle))
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(paired ? Color.white : .clear, lineWidth: 2.5)
                            .padding(-4)
                    }
                    .padding(4)
                Text("Automatica")
                    .font(.caption2)
                    .foregroundStyle(paired ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Segue il colore del Flavor."))
        .accessibilityAddTraits(paired ? .isSelected : [])
        .accessibilityIdentifier("app-icon-automatic")
    }

    /// Every special icon, the one in use ringed. Kept with the shape, so
    /// picking one leaves the app paired.
    private var specialIcons: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(SpecialIcon.allCases) { icon in
                        let chosen = look.app.special == icon
                        Button {
                            withAnimation(.snappy) { look.app.special = icon }
                        } label: {
                            VStack(spacing: 5) {
                                Image(icon.previewImage)
                                    .resizable()
                                    .frame(width: 52, height: 52)
                                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(chosen ? Color.white : .clear, lineWidth: 2.5)
                                            .padding(-4)
                                    }
                                    .padding(4)
                                Text(icon.title)
                                    .font(.caption2)
                                    .foregroundStyle(chosen ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .accessibilityIdentifier("app-icon-special-\(icon.rawValue)")
                        .id(icon)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear { reader.scrollTo(look.app.special, anchor: .center) }
        }
    }

    /// The app's colour for the system picker; picking one unpairs the app.
    private var tintBinding: Binding<Color> {
        Binding {
            look.resolved.appFlavor.base.color
        } set: { colour in
            let resolved = colour.resolve(in: environment)
            look.unpairApp()
            look.app.tint = Flavor(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }
    }

    /// The tab bar's behaviour; choosing one unpairs the app.
    private var tabBarBinding: Binding<TabBarBehaviour> {
        Binding {
            look.appTabBar
        } set: { behaviour in
            withAnimation(.snappy) {
                look.unpairApp()
                look.app.tabBar = behaviour
            }
        }
    }
}

/// The one question at the end of adding a look, as the Lock Screen asks
/// whether to set a wallpaper pair: the page and the app side by side, then
/// pair them or dress the app separately.
struct AppPairQuestion: View {
    /// The look being added.
    let look: TodayStyle
    /// Pairs the app with the page and adds the look.
    let pair: () -> Void
    /// Opens the app half before adding.
    let customise: () -> Void

    /// The view's content.
    var body: some View {
        var paired = look
        paired.pairApp()
        let scale: CGFloat = 0.25
        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                thumbnail("Oggi") {
                    LookScreen(look: paired, scale: scale, cornerRadius: 56)
                }
                thumbnail("App") {
                    AppPreview(look: paired).screenScaled(scale, size: LookScreen.reference)
                }
            }
            Text("L'app prende colore, icona e barra da questo Flavor. Puoi cambiarli quando vuoi da ••• ▸ App.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                Button(action: pair) {
                    Text("Abbina all'app").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("customize-pair")
                Button(action: customise) {
                    Text("Personalizza l'app").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("customize-pair-custom")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .tint(paired.controlTint(.light))
    }

    /// A small screen with its name under it.
    private func thumbnail<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

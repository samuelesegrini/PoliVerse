import SwiftUI

/// The app half of a look, edited the way the Home Screen is next to a Lock
/// Screen: the app drawn as a card on black, and three round buttons under it —
/// Icona, Colore, Barra — each showing its choices in a strip. One is always
/// open, Icona first, with the Home Screen drawn above it.
///
/// Choosing anything by hand unpairs the app from the page; Automatica, first
/// among the icons and the colours, pairs it again and drops those choices.
/// Reached once straight after adding a look, from ``AppPairQuestion``;
/// afterwards the app half is a part of the editor like any other.
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
    private func strip(_ option: Option) -> some View {
        Group {
            switch option {
            case .tint: AppTintPicker(look: $look)
            case .icon: AppIconPicker(look: $look)
            case .bar: AppBarPicker(look: $look)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
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
            Text("L'app prende colore, icona e barra da questo Flavor. Puoi cambiarli quando vuoi nella parte App.")
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

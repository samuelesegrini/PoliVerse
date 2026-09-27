import SwiftUI

/// How a picker lays out its choices: one row that scrolls sideways, as under
/// the page on iPhone, or a grid, as the inspector on iPad and Mac has room for.
enum ChoiceLayout: Equatable {
    /// One row, scrolling sideways.
    case row
    /// Rows of this many.
    case grid(columns: Int)
}

/// Choices laid out in a row or a grid, the row opening on the one in use.
private struct Choices<Content: View>: View {
    /// The layout.
    let layout: ChoiceLayout
    /// The choice to bring into view in a row.
    let current: AnyHashable?
    /// Space between the choices.
    var spacing: CGFloat = 12
    /// The choices.
    @ViewBuilder let content: () -> Content

    /// The view's content.
    var body: some View {
        switch layout {
        case .row:
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) { content() }
                        .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let current { reader.scrollTo(current, anchor: .center) }
                }
            }
        case .grid(let columns):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                      alignment: .leading, spacing: spacing) {
                content()
            }
        }
    }
}

/// One icon to pick: its picture and name, ringed when in use.
private struct IconChoice: View {
    /// The icon's preview image.
    let image: String
    /// What it is called.
    let title: Text
    /// Whether it is the icon in use.
    let chosen: Bool

    /// The view's content.
    var body: some View {
        VStack(spacing: 5) {
            Image(image)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(chosen ? Color.white : .clear, lineWidth: 2.5)
                        .padding(-4)
                }
                .padding(4)
            title
                .font(.caption2)
                .foregroundStyle(chosen ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// The app's icon: its shape, then Automatica and every colour it comes in,
/// or the special pictures; the one in use ringed.
///
/// Choosing a colour by hand unpairs the app from the page; Automatica pairs
/// it again. The shape alone, and a special picture, leave it paired.
struct AppIconPicker: View {
    /// The look whose app half is edited.
    @Binding var look: TodayStyle
    /// How the icons are laid out.
    var layout = ChoiceLayout.row

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSegmentedPicker("Forma", selection: $look.app.iconStyle) { Text($0.title) }
                .accessibilityIdentifier("app-icon-style")
            switch look.appIconStyle {
            case .orbit, .dial, .closeUp: colours
            case .special: specials
            }
        }
    }

    /// Automatica, then every colour of the icon in its shape.
    private var colours: some View {
        Choices(layout: layout, current: look.app.paired ? nil : AnyHashable(look.app.icon)) {
            automatic
            ForEach(AppIconChoice.choices(in: look.appIconStyle)) { choice in
                let chosen = !look.app.paired && look.app.icon == choice
                Button {
                    withAnimation(.snappy) {
                        look.unpairApp()
                        look.app.icon = choice
                    }
                } label: {
                    IconChoice(image: choice.previewImage(in: look.appIconStyle), title: Text(choice.title), chosen: chosen)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("app-icon-\(choice.rawValue)")
                .id(AnyHashable(choice))
            }
        }
    }

    /// The icon nearest the Flavor, in the chosen shape: what a paired app wears.
    private var automatic: some View {
        let paired = look.app.paired
        // Paired, what the app wears now; else what Automatica would give it.
        let shown = paired ? look.resolved.appIcon : AppIconChoice.nearest(to: look.resolved.flavor)
        return Button {
            withAnimation(.snappy) { look.pairApp() }
        } label: {
            IconChoice(image: shown.previewImage(in: look.appIconStyle), title: Text("Automatica"), chosen: paired)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Segue il colore del Flavor."))
        .accessibilityAddTraits(paired ? .isSelected : [])
        .accessibilityIdentifier("app-icon-automatic")
    }

    /// Every special icon, each a picture of its own.
    private var specials: some View {
        Choices(layout: layout, current: AnyHashable(look.app.special)) {
            ForEach(SpecialIcon.allCases) { icon in
                let chosen = look.app.special == icon
                Button {
                    withAnimation(.snappy) { look.app.special = icon }
                } label: {
                    IconChoice(image: icon.previewImage, title: Text(icon.title), chosen: chosen)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("app-icon-special-\(icon.rawValue)")
                .id(AnyHashable(icon))
            }
        }
    }
}

/// The app's colour: Automatico, the system picker for any colour, and the
/// swatches. Any colour but Automatico unpairs the app from the page.
struct AppTintPicker: View {
    /// The look whose app half is edited.
    @Binding var look: TodayStyle
    /// How the swatches are laid out.
    var layout = ChoiceLayout.row

    /// The environment's `self`, to resolve a picked colour.
    @Environment(\.self) private var environment

    /// The view's content.
    var body: some View {
        switch layout {
        case .row:
            Choices(layout: .row, current: look.app.paired ? nil : look.app.tint.map { AnyHashable($0.hex) }) {
                automatic
                picker
                swatches
            }
        case .grid:
            // Automatico is wider than a swatch: it gets a row of its own.
            VStack(alignment: .leading, spacing: 10) {
                automatic
                Choices(layout: layout, current: nil, spacing: 8) {
                    picker
                    swatches
                }
            }
        }
    }

    /// The system picker, for a colour of the student's own.
    private var picker: some View {
        ColorPicker("Altro colore", selection: tintBinding, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 42, height: 42)
    }

    /// One swatch per Flavor colour, the one in use ringed.
    private var swatches: some View {
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
            .id(AnyHashable(swatch.flavor.hex))
        }
    }

    /// The app following the page's colour: the Flavor's own colour, ringed while paired.
    private var automatic: some View {
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
}

/// The iPhone's tab bar: whether it shrinks while scrolling. Choosing
/// unpairs the app from the page.
struct AppBarPicker: View {
    /// The look whose app half is edited.
    @Binding var look: TodayStyle

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSegmentedPicker("Barra", selection: tabBarBinding) { Text($0.title) }
                .accessibilityIdentifier("app-tab-bar")
            Text(look.appTabBar == .minimizes
                 ? "Scorrendo, la barra si riduce alla scheda in cui sei."
                 : "La barra resta intera anche mentre scorri.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

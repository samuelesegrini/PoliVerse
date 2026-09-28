import SwiftUI

/// A look drawn as the app is at full screen size, bars included, then scaled
/// down: Personalizza's cards, the add gallery's thumbnails and the question at
/// the end of adding.
///
/// Drawn at full size and scaled, never laid out small, so the card of the
/// look in use can grow to cover the screen and back without anything inside
/// it moving, and a thumbnail is the page exactly as it will be.
struct LookScreen: View {
    /// The look to draw.
    let look: TodayStyle
    /// How much smaller than the screen it is drawn.
    var scale: CGFloat
    /// The screen it stands for.
    var screen = LookScreen.reference
    /// The screen's safe area, so the bars sit where the system puts them.
    var insets = LookScreen.referenceInsets
    /// The corner radius at full size.
    var cornerRadius: CGFloat = 48

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// A current iPhone's screen, for thumbnails drawn away from the real one.
    static let reference = CGSize(width: 402, height: 874)
    /// That iPhone's safe area.
    static let referenceInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)

    /// The view's content.
    var body: some View {
        // Drawn as the app draws it: a special Flavor's recipe applied.
        let look = self.look.resolved
        // The look's own light, so a dark look reads dark whatever the
        // gallery around it is in.
        let lit = look.appearance.colorScheme ?? scheme
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
                    if look.wantsCurrentClassAccessory, let current = CurrentClass.forAccessory(from: agenda.events(on: .now), now: .now) {
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
        .tint(look.controlTint(lit))
        .background(LookBackground(style: look))
        .environment(\.look, look)
        .environment(\.colorScheme, lit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .screenScaled(scale, size: screen)
        .allowsHitTesting(false)
    }
}

/// What the rest of the app looks like in a look: the Corsi tab, or the Home
/// Screen — or a Mac's Dock — with the look's icon on it.
struct AppPreview: View {
    /// What the preview shows.
    enum Mode: Equatable {
        /// A page of the app, with its tab bar.
        case app
        /// The Home Screen, for the icon.
        case homeScreen
        /// A Mac's desktop, with the icon in the Dock.
        case dock
    }

    /// How the Home Screen draws its icons, as the system lets the student choose.
    enum HomeLook: String, CaseIterable, Identifiable, Hashable {
        /// The icons as drawn.
        case light
        /// Darkened, on a dimmed wallpaper.
        case dark
        /// In one colour.
        case tinted
        /// Clear glass.
        case clear

        /// The choice's identity, which is its raw value.
        var id: String { rawValue }

        /// What the choice is called.
        var title: LocalizedStringKey {
            switch self {
            case .light: "Predefinita"
            case .dark: "Scura"
            case .tinted: "Colorata"
            case .clear: "Trasparente"
            }
        }

        /// How much the wallpaper is dimmed behind the icons.
        var shade: Double {
            switch self {
            case .light: 0
            case .dark: 0.5
            case .tinted: 0.55
            case .clear: 0.2
            }
        }
    }

    /// The look whose app half is drawn.
    let look: TodayStyle
    /// Which of the two to show.
    var mode = Mode.app
    /// Shows the tab bar minimised, when the look lets it minimise.
    var showsMinimizedBar = false
    /// How the Home Screen draws its icons.
    var homeLook = HomeLook.light
    /// The screen it stands for.
    var screen = LookScreen.reference
    /// The screen's safe area.
    var insets = LookScreen.referenceInsets

    /// A preview of a look's app half, drawn with its special Flavor applied.
    init(look: TodayStyle, mode: Mode = .app, showsMinimizedBar: Bool = false, homeLook: HomeLook = .light,
         screen: CGSize = LookScreen.reference, insets: EdgeInsets = LookScreen.referenceInsets) {
        self.look = look.resolved
        self.mode = mode
        self.showsMinimizedBar = showsMinimizedBar
        self.homeLook = homeLook
        self.screen = screen
        self.insets = insets
    }

    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// A few courses, enough to show the tint on rows, progress and links.
    private static let courses: [(code: String, name: LocalizedStringKey, detail: LocalizedStringKey, progress: Double)] = [
        ("AN", "Analisi Matematica II", "10 CFU · 2° semestre", 0.62),
        ("FI", "Fondamenti di Informatica", "10 CFU · 1° semestre", 0.88),
        ("FT", "Fisica Tecnica", "8 CFU · 2° semestre", 0.35),
    ]

    /// The view's content.
    var body: some View {
        Group {
            switch mode {
            case .app: coursesPage
            case .homeScreen: homeScreen
            case .dock: dock
            }
        }
        .frame(width: screen.width, height: screen.height)
        .environment(\.look, look)
        .clipShape(.rect(cornerRadius: 48))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The look's own light, as the app is lit in it.
    private var lit: ColorScheme { look.appearance.colorScheme ?? scheme }

    /// Corsi, drawn in the look: its tint, its cards and its tab bar.
    private var coursesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Corsi")
                .font(.largeTitle.bold())
                .padding(.horizontal, 20)
            VStack(spacing: 10) {
                ForEach(Self.courses.indices, id: \.self) { index in
                    let course = Self.courses[index]
                    HStack(spacing: 12) {
                        Text(course.code)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.tint.opacity(1 - Double(index) * 0.2), in: .rect(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.name).font(.subheadline.weight(.semibold))
                            Text(course.detail).font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: course.progress)
                        }
                    }
                    .padding(14)
                    .todayMaterial(look.material, flavor: look.flavor, mode: look.appearance.flavorMode, cornerRadius: 22)
                }
            }
            .padding(.horizontal, 16)
            Text("Tutti i corsi")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .padding(.top, insets.top + 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            ReplicaTabBar(selected: 1, minimized: showsMinimizedBar && look.appTabBar == .minimizes)
                .padding(.bottom, max(insets.bottom - 13, 0))
        }
        .background(Color(.systemGroupedBackground))
        .tint(look.controlTint(lit))
        .fontDesign(look.textDesign.design)
        .environment(\.colorScheme, lit)
    }

    /// A wallpaper in the app's colour, dimmed as the Home Screen's look asks.
    private var wallpaper: some View {
        let (hue, saturation, _) = look.appFlavor.base.hsb
        let top = Flavor.RGB(hue: hue + 0.04, saturation: saturation * 0.55, brightness: 0.88)
        let bottom = Flavor.RGB(hue: hue - 0.04, saturation: min(saturation * 1.1, 1), brightness: 0.32)
        return LinearGradient(colors: [top.color, bottom.color], startPoint: .top, endPoint: .bottom)
            .overlay { Color.black.opacity(homeLook.shade) }
    }

    /// The look's icon, drawn as the Home Screen's look draws it.
    private func icon(side: CGFloat) -> some View {
        Image(look.appIconPreview)
            .resizable()
            .frame(width: side, height: side)
            .modifier(HomeIconLook(look: homeLook))
            .clipShape(.rect(cornerRadius: side * 0.234, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    /// Another app's place: a plain tile in the Home Screen's look.
    private func otherApp(side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.234, style: .continuous)
        return shape
            .fill(homeLook.otherAppFill)
            .overlay {
                if homeLook == .clear { shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.5) }
            }
            .frame(width: side, height: side)
    }

    /// A Home Screen on a wallpaper in the app's colour, with the look's icon
    /// among the others: four across on an iPhone, six on an iPad.
    private var homeScreen: some View {
        let columns = screen.width > 600 ? 6 : 4
        return ZStack(alignment: .top) {
            wallpaper
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 22) {
                ForEach(0..<(columns * 5), id: \.self) { index in
                    VStack(spacing: 6) {
                        if index == 5 {
                            icon(side: 64)
                            Text(verbatim: "PoliVerse")
                        } else {
                            otherApp(side: 64)
                            Text(verbatim: " ")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, insets.top + 28)
            HStack {
                ForEach(0..<4, id: \.self) { _ in
                    otherApp(side: 62)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92)
            .frame(maxWidth: columns > 4 ? 420 : .infinity)
            .background(.white.opacity(0.18), in: .rect(cornerRadius: 36, style: .continuous))
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 14)
        }
    }

    /// A Mac's desktop: the menu bar at the top and the Dock at the bottom,
    /// the look's icon in it.
    private var dock: some View {
        ZStack {
            wallpaper
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "apple.logo")
                    Text(verbatim: "PoliVerse").fontWeight(.bold)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 26)
                .background(.black.opacity(0.18))
                Spacer()
                HStack(spacing: 10) {
                    ForEach(0..<9, id: \.self) { index in
                        if index == 3 {
                            icon(side: 56)
                        } else {
                            otherApp(side: 56)
                        }
                    }
                }
                .padding(10)
                .background(.white.opacity(0.22), in: .rect(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 10)
            }
        }
    }
}

extension AppPreview.HomeLook {
    /// Another app's tile in this look.
    fileprivate var otherAppFill: Color {
        switch self {
        case .light: .white.opacity(0.22)
        case .dark: Color(white: 0.1).opacity(0.75)
        case .tinted: HomeIconLook.tint.opacity(0.28)
        case .clear: .white.opacity(0.2)
        }
    }
}

/// An icon as the Home Screen's look draws it: darkened, in one colour, or
/// clear. The system derives these from the icon; this is an impression of it.
private struct HomeIconLook: ViewModifier {
    /// The Home Screen's look.
    let look: AppPreview.HomeLook

    /// The colour tinted icons take.
    static let tint = Color(red: 0x8F / 255, green: 0xD9 / 255, blue: 0xCC / 255)

    /// The icon, drawn in the look.
    func body(content: Content) -> some View {
        switch look {
        case .light:
            content
        case .dark:
            content
                .colorMultiply(Color(white: 0.72))
                .contrast(1.08)
        case .tinted:
            content
                .grayscale(1)
                .contrast(1.15)
                .colorMultiply(Color(white: 0.9))
                .overlay { Self.tint.opacity(0.55) }
        case .clear:
            content
                .grayscale(1)
                .brightness(0.18)
                .contrast(0.85)
                .opacity(0.9)
                .overlay { Color.white.opacity(0.12) }
        }
    }
}

extension View {
    /// A screen-sized view drawn smaller: scaled about its centre, then given
    /// the smaller frame, so it lays out at full size and takes the room of
    /// its scaled copy.
    ///
    /// - Parameters:
    ///   - scale: How much smaller.
    ///   - size: Its full size.
    /// - Returns: The scaled view.
    func screenScaled(_ scale: CGFloat, size: CGSize) -> some View {
        scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }
}

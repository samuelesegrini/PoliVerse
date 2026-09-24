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
/// Screen with the look's icon on it.
struct AppPreview: View {
    /// What the preview shows.
    enum Mode: Equatable {
        /// A page of the app, with its tab bar.
        case app
        /// The Home Screen, for the icon.
        case homeScreen
    }

    /// The look whose app half is drawn.
    let look: TodayStyle
    /// Which of the two to show.
    var mode = Mode.app
    /// Shows the tab bar minimised, when the look lets it minimise.
    var showsMinimizedBar = false
    /// The screen it stands for.
    var screen = LookScreen.reference
    /// The screen's safe area.
    var insets = LookScreen.referenceInsets

    /// A preview of a look's app half, drawn with its special Flavor applied.
    init(look: TodayStyle, mode: Mode = .app, showsMinimizedBar: Bool = false,
         screen: CGSize = LookScreen.reference, insets: EdgeInsets = LookScreen.referenceInsets) {
        self.look = look.resolved
        self.mode = mode
        self.showsMinimizedBar = showsMinimizedBar
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

    /// A Home Screen on a wallpaper in the app's colour, with the look's icon
    /// among the others.
    private var homeScreen: some View {
        let (hue, saturation, _) = look.appFlavor.base.hsb
        let top = Flavor.RGB(hue: hue + 0.04, saturation: saturation * 0.55, brightness: 0.88)
        let bottom = Flavor.RGB(hue: hue - 0.04, saturation: min(saturation * 1.1, 1), brightness: 0.32)
        return ZStack(alignment: .top) {
            LinearGradient(colors: [top.color, bottom.color], startPoint: .top, endPoint: .bottom)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 22) {
                ForEach(0..<20, id: \.self) { index in
                    VStack(spacing: 6) {
                        if index == 5 {
                            Image(look.appIcon.previewImage)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 15, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            Text(verbatim: "PoliVerse")
                        } else {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(.white.opacity(0.22))
                                .frame(width: 64, height: 64)
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
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.22))
                        .frame(width: 62, height: 62)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92)
            .background(.white.opacity(0.18), in: .rect(cornerRadius: 36, style: .continuous))
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 14)
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

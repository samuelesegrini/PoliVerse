import SwiftUI

/// The colours the whole app draws with.
///
/// ``brand`` is whatever the look in use puts on its controls, resolved through the
/// environment's tint rather than named at each site — so every icon, bar and badge
/// follows Personalizza without knowing about it.
///
/// ``courseAccents`` are the eight per-course accents, chosen to stay distinguishable in
/// both light and dark and under the common forms of colour blindness, and each with a
/// lighter dark-mode twin so a mid-tone that reads on white does not lose contrast on
/// near-black. Every pair clears 4.5:1 against its own background.
enum Theme {
    /// The app's own colour: the look's tint where one is set, and the `AccentColor` asset
    /// otherwise.
    ///
    /// The fallback covers the sign-in and first-run screens, which run before there is a
    /// look to speak of. The asset is adaptive, because the light-mode navy scores about
    /// 1.3:1 on a dark background.
    static let brand = Color.accentColor

    /// ``brand`` as components, which a ``GlassTile`` needs rather than an adaptive `Color`.
    ///
    /// - Parameter dark: Whether the interface is in dark mode.
    /// - Returns: The colour's components.
    static func brandRGB(dark: Bool) -> Flavor.RGB {
        dark ? Flavor.RGB(red: 0.35, green: 0.65, blue: 0.88)
             : Flavor.RGB(red: 0.00, green: 0.20, blue: 0.32)
    }

    /// The eight per-course accents, as adaptive colours.
    static let courseAccents: [Color] = courseAccentComponents.map { adaptive(light: $0.light, dark: $0.dark) }

    /// The eight accents as light and dark component pairs. The orange and the ochre are
    /// darkened in light mode to clear 4.5:1.
    private static let courseAccentComponents: [(light: (Double, Double, Double), dark: (Double, Double, Double))] = [
        ((0.11, 0.42, 0.68), (0.42, 0.68, 0.94)),
        ((0.72, 0.30, 0.12), (0.96, 0.55, 0.32)),
        ((0.20, 0.51, 0.36), (0.40, 0.78, 0.57)),
        ((0.51, 0.24, 0.60), (0.76, 0.53, 0.88)),
        ((0.72, 0.18, 0.35), (0.95, 0.45, 0.58)),
        ((0.15, 0.45, 0.55), (0.38, 0.75, 0.85)),
        ((0.52, 0.39, 0.09), (0.89, 0.72, 0.30)),
        ((0.33, 0.35, 0.72), (0.58, 0.62, 0.95)),
    ]

    /// One course accent as components, for the pages that build a ramp of colours around it.
    ///
    /// - Parameters:
    ///   - index: The accent's index, wrapped to the eight available.
    ///   - dark: Whether the interface is in dark mode.
    /// - Returns: The colour's components.
    static func courseAccentRGB(_ index: Int, dark: Bool) -> Flavor.RGB {
        let parts = courseAccentComponents[index % courseAccentComponents.count]
        let c = dark ? parts.dark : parts.light
        return Flavor.RGB(red: c.0, green: c.1, blue: c.2)
    }

    /// A colour that resolves differently in light and dark mode.
    ///
    /// - Parameters:
    ///   - light: The light-mode components.
    ///   - dark: The dark-mode components.
    /// - Returns: The adaptive colour.
    private static func adaptive(
        light: (Double, Double, Double), dark: (Double, Double, Double)
    ) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// The label colour for text sitting on a filled accent surface.
    ///
    /// The accents invert between modes — dark navy on white, light blue on black — so a
    /// fixed white label works in light mode and scores about 2.3:1 in dark. Near-black on
    /// the lighter dark-mode accent gives roughly 9:1.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : .white
    })

    /// The accent a course keeps between launches, from its ``Course/colorSeed``.
    ///
    /// - Parameter course: The course.
    /// - Returns: Its accent.
    static func accent(for course: Course) -> Color {
        courseAccents[course.colorSeed % courseAccents.count]
    }

    /// The corner radius every card in the app is drawn with.
    static let cardCorner: CGFloat = 26
}

// A card is drawn one way in this app: `lookCard()`, which paints the material
// the student chose in Personalizza. There is deliberately no fixed background
// here to opt out with.

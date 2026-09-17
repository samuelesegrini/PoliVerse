import SwiftUI

enum Theme {
    /// Politecnico blue as the anchor, with a deterministic accent per course.
    ///
    /// This must be adaptive. The light-mode navy is `rgb(0, 51, 82)`, which
    /// scores about 1.3:1 against the dark-mode background — far under the
    /// 4.5:1 minimum, and effectively invisible as a tint on the tab bar. The
    /// dark variant is the same hue lifted into a readable range.
    static let brand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.65, blue: 0.88, alpha: 1)
            : UIColor(red: 0.00, green: 0.20, blue: 0.32, alpha: 1)
    })

    /// Eight accents chosen to stay distinguishable in both light and dark and
    /// to remain distinct for the common forms of colour blindness — they vary
    /// in lightness, not only hue.
    ///
    /// Each is given a lighter dark-mode twin for the same reason as ``brand``:
    /// a mid-tone that reads well on white loses contrast on near-black.
    ///
    /// Every pair clears 4.5:1 against its own background. The orange and ochre
    /// needed darkening in light mode to get there.
    static let courseAccents: [Color] = courseAccentComponents.map { adaptive(light: $0.light, dark: $0.dark) }

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

    /// A course accent as components, for the pages that build a ramp of
    /// colours around it.
    static func courseAccentRGB(_ index: Int, dark: Bool) -> Flavor.RGB {
        let parts = courseAccentComponents[index % courseAccentComponents.count]
        let c = dark ? parts.dark : parts.light
        return Flavor.RGB(red: c.0, green: c.1, blue: c.2)
    }

    private static func adaptive(
        light: (Double, Double, Double), dark: (Double, Double, Double)
    ) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Label colour for text sitting *on* a filled accent surface.
    ///
    /// The accents invert between modes — dark navy on white, light blue on
    /// black — so a fixed white label works in light mode and scores about
    /// 2.3:1 in dark. Flipping to near-black on the light dark-mode accent
    /// gives roughly 9:1.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : .white
    })

    static func accent(for course: Course) -> Color {
        courseAccents[course.colorSeed % courseAccents.count]
    }

    static let cardCorner: CGFloat = 26
}

extension View {
    /// Standard card treatment, so radius and shadow are defined once.
    func cardBackground(_ tint: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        background(tint, in: .rect(cornerRadius: Theme.cardCorner))
    }
}

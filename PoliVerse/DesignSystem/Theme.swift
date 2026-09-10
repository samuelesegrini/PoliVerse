import SwiftUI

enum Theme {
    /// Politecnico blue as the anchor, with a deterministic accent per course.
    static let brand = Color(red: 0.0, green: 0.20, blue: 0.32)

    /// Eight accents chosen to stay distinguishable in both light and dark and
    /// to remain distinct for the common forms of colour blindness — they vary
    /// in lightness, not only hue.
    static let courseAccents: [Color] = [
        Color(red: 0.11, green: 0.42, blue: 0.68),
        Color(red: 0.78, green: 0.33, blue: 0.13),
        Color(red: 0.20, green: 0.51, blue: 0.36),
        Color(red: 0.51, green: 0.24, blue: 0.60),
        Color(red: 0.72, green: 0.18, blue: 0.35),
        Color(red: 0.15, green: 0.45, blue: 0.55),
        Color(red: 0.60, green: 0.45, blue: 0.10),
        Color(red: 0.33, green: 0.35, blue: 0.72),
    ]

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

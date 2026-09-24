import SwiftUI
import UIKit

/// The other half of a look: what the rest of the app wears with the page.
///
/// A look is two things, like a Lock Screen and its Home Screen. The page is
/// Oggi; the app is the tint on every control, the icon on the Home Screen and
/// how the tab bar behaves. Paired, the app takes all three from the page — the
/// Flavor's accent, the icon nearest the Flavor, the usual bar — and follows
/// it as it changes. Choosing any of them by hand unpairs it, and from then on
/// the app keeps its own.
///
/// Asked once, when a look is added; afterwards only from the editor's
/// ••• ▸ App.
nonisolated struct AppLook: Codable, Equatable, Hashable, Sendable {
    /// The app takes its tint, icon and bar from the page.
    var paired = true
    /// The app's own colour, when unpaired.
    var tint: Flavor?
    /// The app's own icon, when unpaired.
    var icon = AppIconChoice.classic
    /// The tab bar's own behaviour, when unpaired.
    var tabBar = TabBarBehaviour.minimizes

    /// Paired: the app follows the page.
    init() {}

    /// Reads an app half, keeping the defaults for anything a stored look does not name.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: Whatever the decoder throws.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paired = try container.decodeIfPresent(Bool.self, forKey: .paired) ?? paired
        tint = try? container.decodeIfPresent(Flavor.self, forKey: .tint)
        icon = (try? container.decodeIfPresent(AppIconChoice.self, forKey: .icon)) ?? icon
        tabBar = (try? container.decodeIfPresent(TabBarBehaviour.self, forKey: .tabBar)) ?? tabBar
    }
}

/// The icons the app can wear on the Home Screen: the one it ships with, a
/// dark and a light one, and one per Flavor swatch.
///
/// Built by `scripts/build-alternate-icons.py`, which keeps the ids here and
/// the asset names in step.
nonisolated enum AppIconChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The shipped icon, then a dark and a light ground.
    case classic, dark, light
    /// One per ``Flavor/swatches``, after Blu Politecnico, which is the classic.
    case lavender, indigo, sky, mint, sage, mandarin, coral, raspberry, coffee, slate, graphite

    /// The icon's identity, which is its raw value.
    var id: String { rawValue }

    /// What the icon is called in Personalizza.
    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classica"
        case .dark: "Scura"
        case .light: "Chiara"
        case .lavender: "Lavanda"
        case .indigo: "Indaco"
        case .sky: "Cielo"
        case .mint: "Menta"
        case .sage: "Salvia"
        case .mandarin: "Mandarino"
        case .coral: "Corallo"
        case .raspberry: "Lampone"
        case .coffee: "Caffè"
        case .slate: "Ardesia"
        case .graphite: "Grafite"
        }
    }

    /// The name the system knows the icon by; `nil` for the primary icon.
    var alternateIconName: String? {
        self == .classic ? nil : "AppIcon-\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }

    /// The small copy drawn inside the app, since an icon set is not an image.
    var previewImage: String { "AppIconPreview-\(rawValue)" }

    /// The swatch colour a Flavor icon is built on; `nil` for classic, dark and light.
    var swatch: Flavor.RGB? {
        let hex: String? = switch self {
        case .classic, .dark, .light: nil
        case .lavender: "#7A6FE0"
        case .indigo: "#3B4BC8"
        case .sky: "#2E9BD6"
        case .mint: "#2FA88A"
        case .sage: "#5E8C61"
        case .mandarin: "#E8751A"
        case .coral: "#E0584F"
        case .raspberry: "#C2386F"
        case .coffee: "#8A5A3C"
        case .slate: "#5B6472"
        case .graphite: "#1F2328"
        }
        return hex.flatMap(Flavor.RGB.init(hex:))
    }

    /// The icon closest in colour to a Flavor: what a paired app wears.
    ///
    /// - Parameter flavor: The page's Flavor.
    /// - Returns: The classic icon for the Politecnico's navy and its
    ///   neighbours, otherwise the nearest swatch icon.
    static func nearest(to flavor: Flavor) -> AppIconChoice {
        let candidates: [(AppIconChoice, Flavor.RGB)] = [(.classic, Flavor.polimi.base)]
            + allCases.compactMap { choice in choice.swatch.map { (choice, $0) } }
        func distance(_ a: Flavor.RGB, _ b: Flavor.RGB) -> Double {
            let red = a.red - b.red, green = a.green - b.green, blue = a.blue - b.blue
            return red * red + green * green + blue * blue
        }
        return candidates.min { distance($0.1, flavor.base) < distance($1.1, flavor.base) }?.0 ?? .classic
    }
}

/// How the tab bar behaves while a page scrolls.
nonisolated enum TabBarBehaviour: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Shrinks to the selected tab while scrolling down, as the system suggests.
    case minimizes
    /// Stays whole.
    case stays

    /// The behaviour's identity, which is its raw value.
    var id: String { rawValue }

    /// What the behaviour is called in Personalizza.
    var title: LocalizedStringKey {
        switch self {
        case .minimizes: "Si riduce"
        case .stays: "Sempre intera"
        }
    }

    /// The behaviour as the tab view takes it.
    var system: TabBarMinimizeBehavior {
        switch self {
        case .minimizes: .onScrollDown
        case .stays: .never
        }
    }
}

// MARK: - The look's app half, resolved

nonisolated extension TodayStyle {
    /// The colour the app is tinted from: the page's Flavor while paired.
    var appFlavor: Flavor { app.paired ? flavor : (app.tint ?? flavor) }

    /// The icon the app wears: the one nearest the Flavor while paired.
    var appIcon: AppIconChoice { app.paired ? .nearest(to: flavor) : app.icon }

    /// How the tab bar behaves: the usual while paired.
    var appTabBar: TabBarBehaviour { app.paired ? .minimizes : app.tabBar }

    /// Takes the app off the page, keeping what it wears now as its own, so
    /// the first choice made by hand changes only that one thing.
    mutating func unpairApp() {
        guard app.paired else { return }
        // Read while still paired: afterwards these read the app's own.
        let (tint, icon, tabBar) = (appFlavor, appIcon, appTabBar)
        app.paired = false
        app.tint = tint
        app.icon = icon
        app.tabBar = tabBar
    }

    /// Puts the app back on the page, dropping its own choices.
    mutating func pairApp() {
        app = AppLook()
    }
}

// MARK: - Applying the icon

/// Puts the look's icon on the Home Screen.
enum AppIconSwitcher {
    /// Sets the icon, when it differs from the one showing. The system tells
    /// the student with an alert of its own, so this runs once, when
    /// Personalizza closes, and never while swiping through looks.
    ///
    /// - Parameter choice: The icon to wear.
    static func apply(_ choice: AppIconChoice) async {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons,
              application.alternateIconName != choice.alternateIconName else { return }
        try? await application.setAlternateIconName(choice.alternateIconName)
    }
}

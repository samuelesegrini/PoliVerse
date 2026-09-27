import Foundation
import Testing
import UIKit
@testable import PoliVerse

/// A look's app half: paired it follows the page, unpaired it keeps its own
/// tint, icon and tab bar, and it survives storage.
@Suite("App look")
struct AppLookTests {
    @Test("Paired, the app takes its tint, icon and bar from the page")
    func paired() throws {
        var look = TodayStyle()
        look.flavor = try #require(Flavor(hex: "#E8751A"))
        #expect(look.app.paired)
        #expect(look.appFlavor == look.flavor)
        #expect(look.appIcon == .mandarin)
        #expect(look.appTabBar == .minimizes)
        #expect(look.controlAccent(dark: false) == look.flavor.accent(dark: false))
    }

    @Test("Unpairing keeps what the app wears, then only the choice made changes")
    func unpair() throws {
        var look = TodayStyle()
        look.flavor = try #require(Flavor(hex: "#2FA88A"))
        look.unpairApp()
        #expect(!look.app.paired)
        #expect(look.appFlavor == look.flavor)
        #expect(look.appIcon == .mint)

        look.app.icon = .graphite
        look.flavor = try #require(Flavor(hex: "#C2386F"))
        #expect(look.appIcon == .graphite, "An unpaired app followed the page's icon")
        #expect(look.appFlavor.hex == "#2FA88A", "An unpaired app followed the page's colour")

        let tint = try #require(Flavor(hex: "#3B4BC8"))
        look.app.tint = tint
        #expect(look.controlAccent(dark: true) == tint.accent(dark: true))
    }

    @Test("Pairing again drops the app's own choices")
    func pairAgain() {
        var look = TodayStyle()
        look.unpairApp()
        look.app.icon = .coral
        look.app.tabBar = .stays
        look.pairApp()
        #expect(look.app == AppLook())
        #expect(look.appTabBar == .minimizes)
    }

    @Test("The paired icon is the one nearest the Flavor")
    func nearest() throws {
        #expect(AppIconChoice.nearest(to: .polimi) == .classic)
        for choice in AppIconChoice.allCases {
            guard let swatch = choice.swatch else { continue }
            #expect(AppIconChoice.nearest(to: Flavor(main: swatch)) == choice)
        }
    }

    @Test("Orbita's own ground is the shipped icon; every shape names its colours")
    func assets() {
        #expect(AppIconChoice.classic.alternateIconName(in: .orbit) == nil)
        #expect(AppIconChoice.lavender.alternateIconName(in: .orbit) == "AppIcon-Orbit-Lavender")
        #expect(AppIconChoice.lavender.previewImage(in: .orbit) == "AppIconPreview-orbit-lavender")
        #expect(AppIconChoice.choices(in: .orbit) == AppIconChoice.allCases)
        #expect(AppIconChoice.choices(in: .special).isEmpty)
        #expect(AppIconChoice.classic.alternateIconName(in: .dial) == "AppIcon-Dial")
        #expect(AppIconChoice.lavender.alternateIconName(in: .closeUp) == "AppIcon-CloseUp-Lavender")
        #expect(UIImage(named: "AppIconPreview-classic") != nil)
    }

    @Test("Round-trips through the stored look; an older look comes back paired")
    func storage() throws {
        var look = TodayStyle()
        look.unpairApp()
        look.app.icon = .graphite
        look.app.tabBar = .stays
        look.app.tint = Flavor(hex: "#5E8C61")
        let restored = try #require(TodayStyle(rawValue: look.rawValue))
        #expect(restored.app == look.app)

        let older = try #require(TodayStyle(rawValue: ##"{"flavor":"#8A5A3C"}"##))
        #expect(older.app.paired)
        // Saved before Orbita came in colours: it keeps its classic blue.
        #expect(older.appIcon == .classic)
        #expect(older.appIconName == nil)
    }

    @Test("Only new looks wear Orbita in the Flavor's colour; a saved one keeps it blue until Automatica is chosen")
    func colouredOrbitForNewLooks() throws {
        let coffee = try #require(Flavor(hex: "#8A5A3C"))

        // A new look, paired, in Orbita: the colour nearest the Flavor, kept through storage.
        var fresh = TodayStyle()
        fresh.flavor = coffee
        #expect(fresh.appIconName == "AppIcon-Orbit-Coffee")
        let stored = try #require(TodayStyle(rawValue: fresh.rawValue))
        #expect(stored.appIconName == "AppIcon-Orbit-Coffee")

        // Saved before: the same look keeps the shipped icon.
        var saved = try #require(TodayStyle(rawValue: ##"{"flavor":"#8A5A3C","app":{"paired":true}}"##))
        #expect(saved.appIconName == nil)
        #expect(saved.appIconPreview == "AppIconPreview-classic")

        // The other shapes always followed the Flavor, and still do.
        saved.app.iconStyle = .dial
        #expect(saved.appIcon == .coffee)
        saved.app.iconStyle = .orbit

        // Unpairing keeps what it wears: the blue.
        var unpaired = saved
        unpaired.unpairApp()
        #expect(unpaired.app.icon == .classic)

        // Choosing Automatica is choosing the colour.
        saved.pairApp()
        #expect(saved.appIconName == "AppIcon-Orbit-Coffee")
    }

    @Test("Every shape and colour names an icon the app ships, and a preview it can draw")
    func shapesNameShippedIcons() throws {
        let plist = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternates = try #require(plist["CFBundleAlternateIcons"] as? [String: Any])
        for style in AppIconStyle.allCases {
            for choice in AppIconChoice.choices(in: style) {
                if let name = choice.alternateIconName(in: style) {
                    #expect(alternates[name] != nil, "\(name) is not in the app")
                }
                #expect(UIImage(named: choice.previewImage(in: style)) != nil,
                        "\(choice.previewImage(in: style)) is missing")
            }
        }
        for icon in SpecialIcon.allCases {
            #expect(alternates[icon.alternateIconName] != nil, "\(icon.alternateIconName) is not in the app")
            #expect(UIImage(named: icon.previewImage) != nil, "\(icon.previewImage) is missing")
        }
    }

    @Test("A special icon is worn whatever the colour, and kept on pairing")
    func specialIcon() {
        var look = TodayStyle()
        look.app.iconStyle = .special
        look.app.special = .leather
        #expect(look.appIconName == "AppIcon-Leather")
        #expect(look.appIconPreview == "AppIconPreview-special-leather")
        look.pairApp()
        #expect(look.appIconName == "AppIcon-Leather")
    }

    @Test("A paired Orbita wears the colour nearest the Flavor; the Politecnico's is the shipped icon")
    func pairedOrbitFollowsFlavor() throws {
        var look = TodayStyle()
        look.app.iconStyle = .orbit
        look.flavor = try #require(Flavor(hex: "#2FA88A"))
        #expect(look.appIconName == "AppIcon-Orbit-Mint")
        #expect(look.appIconPreview == "AppIconPreview-orbit-mint")
        look.flavor = .polimi
        #expect(look.appIconName == nil)
    }

    @Test("Pairing again keeps the icon's shape, and the shape reaches the icon's name")
    func shapeSurvivesPairing() {
        var look = TodayStyle()
        look.app.iconStyle = .dial
        look.unpairApp()
        look.app.icon = .mint
        #expect(look.appIconName == "AppIcon-Dial-Mint")
        look.pairApp()
        #expect(look.app.iconStyle == .dial)
        #expect(look.appIconName?.hasPrefix("AppIcon-Dial") == true)
    }
}

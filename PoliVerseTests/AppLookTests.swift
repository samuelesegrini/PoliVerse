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

        look.app.icon = .dark
        look.flavor = try #require(Flavor(hex: "#C2386F"))
        #expect(look.appIcon == .dark, "An unpaired app followed the page's icon")
        #expect(look.appFlavor.hex == "#2FA88A", "An unpaired app followed the page's colour")

        let tint = try #require(Flavor(hex: "#3B4BC8"))
        look.app.tint = tint
        #expect(look.controlAccent(dark: true) == tint.accent(dark: true))
    }

    @Test("Pairing again drops the app's own choices")
    func pairAgain() {
        var look = TodayStyle()
        look.unpairApp()
        look.app.icon = .light
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

    @Test("Every icon has its asset names and a preview to draw")
    func assets() {
        #expect(AppIconChoice.classic.alternateIconName == nil)
        #expect(AppIconChoice.lavender.alternateIconName == "AppIcon-Lavender")
        for choice in AppIconChoice.allCases {
            #expect(UIImage(named: choice.previewImage) != nil, "No preview for \(choice.rawValue)")
        }
    }

    @Test("Round-trips through the stored look; an older look comes back paired")
    func storage() throws {
        var look = TodayStyle()
        look.unpairApp()
        look.app.icon = .graphite
        look.app.tabBar = .stays
        look.app.tint = try #require(Flavor(hex: "#5E8C61"))
        let restored = try #require(TodayStyle(rawValue: look.rawValue))
        #expect(restored.app == look.app)

        let older = try #require(TodayStyle(rawValue: ##"{"flavor":"#8A5A3C"}"##))
        #expect(older.app.paired)
        #expect(older.appIcon == .coffee)
    }
}

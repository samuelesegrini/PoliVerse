import Foundation
import Testing
@testable import PoliVerse

/// Flavor's second pass: three colours instead of one, a name, colours taken
/// from a photo, a code to share it by, and the Contrast and Tinted modes.
@Suite("Flavor v2")
struct FlavorV2Tests {
    private func hueDistance(_ a: Flavor.RGB, _ b: Flavor.RGB) -> Double {
        let d = abs(a.hsb.hue - b.hsb.hue)
        return min(d, 1 - d)
    }

    @Test("A main colour alone gives an accent and an extra of neighbouring hues, the same every time")
    func derived() throws {
        let flavor = try #require(Flavor(hex: "#FF0080"))
        #expect(flavor.main == flavor.base)
        #expect(hueDistance(flavor.main, flavor.accentColour) > 0.04)
        #expect(hueDistance(flavor.main, flavor.extraColour) > hueDistance(flavor.main, flavor.accentColour))
        #expect(Flavor(hex: "#FF0080")!.accentColour == flavor.accentColour)
    }

    @Test("Accent and extra can be set by hand, and are kept")
    func overridden() throws {
        var flavor = try #require(Flavor(hex: "#FF0080"))
        let purple = try #require(Flavor(hex: "#8030A0")).base
        flavor.accentColour = purple
        #expect(flavor.accentColour == purple)
        flavor.resetDerived()
        #expect(flavor.accentColour != purple)
    }

    @Test("Every role stays readable on the ground and on cards, in every mode and scheme")
    func rolesReadable() {
        var generator = SeededGenerator(seed: 9)
        let flavors = Flavor.swatches.map(\.flavor) + (0..<60).map { _ in
            Flavor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                   blue: .random(in: 0...1, using: &generator))
        }
        for flavor in flavors {
            for mode in Flavor.Mode.allCases {
                for dark in [false, true] {
                    for role in Flavor.Role.allCases {
                        let colour = flavor.readable(role, dark: dark, mode: mode)
                        #expect(Flavor.contrast(colour, flavor.ground(dark: dark, mode: mode)) >= 3,
                                "\(flavor.hex) \(role) \(mode) \(dark) on ground")
                        #expect(Flavor.contrast(colour, flavor.surface(dark: dark, mode: mode)) >= 3,
                                "\(flavor.hex) \(role) \(mode) \(dark) on cards")
                    }
                }
            }
        }
    }

    @Test("Contrast mode is pure white or black behind; Tinted is visibly more coloured than standard")
    func modes() throws {
        let flavor = try #require(Flavor(hex: "#7A6FE0"))
        #expect(flavor.ground(dark: false, mode: .contrast) == .white)
        #expect(flavor.ground(dark: true, mode: .contrast) == .black)
        #expect(flavor.ground(dark: false, mode: .tinted).hsb.saturation > flavor.ground(dark: false).hsb.saturation * 1.5)
        #expect(flavor.surface(dark: false, mode: .tinted).hsb.saturation > flavor.surface(dark: false).hsb.saturation)
    }

    @Test("A Flavor is named after its hue, with a playful stretch; greys have their own names")
    func names() throws {
        #expect(try #require(Flavor(hex: "#2E6BE6")).name == "Bluuu")
        #expect(try #require(Flavor(hex: "#E8751A")).name == "Tostatooo")
        #expect(try #require(Flavor(hex: "#4CAF50")).name == "Frescooo")
        #expect(try #require(Flavor(hex: "#5B5B5B")).name == "Grafiteee")
        #expect(try #require(Flavor(hex: "#E6E6E6")).name == "Nuvolaaa")
    }

    @Test("A share code carries all three colours and comes back as the same Flavor; anything else is refused")
    func shareCode() throws {
        var flavor = try #require(Flavor(hex: "#FF0080"))
        flavor.extraColour = try #require(Flavor(hex: "#1040A0")).base
        let code = flavor.shareCode
        #expect(code.hasPrefix("poliverse-flavor:"))
        let received = try #require(Flavor(shareCode: code))
        for role in Flavor.Role.allCases {
            #expect(received.colour(role).hex == flavor.colour(role).hex, "\(role)")
        }
        #expect(Flavor(shareCode: "poliverse-flavor:#FF0080") != nil)
        #expect(Flavor(shareCode: "flavor:#FF0080,#000000,#FFFFFF") == nil)
        #expect(Flavor(shareCode: "poliverse-flavor:pink") == nil)
    }

    @Test("Stored as an object with three colours; a plain hex from before still reads")
    func codable() throws {
        var flavor = try #require(Flavor(hex: "#2FA88A"))
        flavor.accentColour = try #require(Flavor(hex: "#123456")).base
        let data = try JSONEncoder().encode(flavor)
        #expect(try JSONDecoder().decode(Flavor.self, from: data) == flavor)
        let legacy = try JSONDecoder().decode(Flavor.self, from: Data("\"#2FA88A\"".utf8))
        #expect(legacy == Flavor(hex: "#2FA88A"))
    }

    // MARK: From a photo

    private func pixels(_ spec: [(String, Int)]) -> [Flavor.RGB] {
        spec.flatMap { hex, count in Array(repeating: Flavor(hex: hex)!.base, count: count) }
    }

    @Test("From a photo: the most present vivid colour is main, then the next two distinct hues")
    func extraction() throws {
        let photo = pixels([("#FF0080", 300), ("#F2F2F2", 400), ("#8030A0", 160), ("#1040A0", 90), ("#202020", 50), ("#FF1A8C", 40)])
        let flavor = try #require(Flavor.extract(from: photo))
        #expect(hueDistance(flavor.main, Flavor(hex: "#FF0080")!.base) < 0.03)
        #expect(hueDistance(flavor.accentColour, Flavor(hex: "#8030A0")!.base) < 0.03)
        #expect(hueDistance(flavor.extraColour, Flavor(hex: "#1040A0")!.base) < 0.03)
    }

    @Test("A photo with one colour still gives three; a grey photo gives a grey Flavor; nothing gives nothing")
    func extractionEdges() throws {
        let single = try #require(Flavor.extract(from: pixels([("#2FA88A", 500)])))
        #expect(hueDistance(single.main, Flavor(hex: "#2FA88A")!.base) < 0.03)
        let grey = try #require(Flavor.extract(from: pixels([("#808080", 200), ("#404040", 200)])))
        #expect(grey.main.hsb.saturation < 0.1)
        #expect(Flavor.extract(from: []) == nil)
    }
}

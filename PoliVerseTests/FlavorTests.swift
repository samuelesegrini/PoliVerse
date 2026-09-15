import Foundation
import Testing
@testable import PoliVerse

/// A Flavor turns one base colour into a whole page: its ground, its cards,
/// an accent that stays readable, and the text on that accent.
@Suite("Flavor")
struct FlavorTests {
    /// A spread of hard cases: pale and dark, saturated and grey, plus a seeded
    /// scatter across the whole cube.
    private static var colours: [Flavor] {
        var generator = SeededGenerator(seed: 42)
        let fixed = ["#FFFFFF", "#000000", "#FFFF00", "#00FFFF", "#0F3D6E", "#7A6FE0", "#808080", "#FF0000", "#1A1A2E", "#F5E6CC"]
            .compactMap(Flavor.init(hex:))
        let scattered = (0..<150).map { _ in
            Flavor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                   blue: .random(in: 0...1, using: &generator))
        }
        return fixed + Flavor.swatches.map(\.flavor) + scattered
    }

    @Test("Reads and writes hex, and refuses what is not a colour")
    func hex() throws {
        let flavor = try #require(Flavor(hex: "#7A6FE0"))
        #expect(flavor.hex == "#7A6FE0")
        #expect(Flavor(hex: "7a6fe0")?.hex == "#7A6FE0")
        #expect(Flavor(hex: "#12345") == nil)
        #expect(Flavor(hex: "purple") == nil)
    }

    @Test("Contrast follows WCAG: black on white is 21, a colour on itself is 1")
    func contrast() {
        let white = Flavor.RGB(red: 1, green: 1, blue: 1), black = Flavor.RGB(red: 0, green: 0, blue: 0)
        #expect(abs(Flavor.contrast(black, white) - 21) < 0.01)
        #expect(abs(Flavor.contrast(white, black) - 21) < 0.01)
        #expect(abs(Flavor.contrast(white, white) - 1) < 0.0001)
    }

    @Test("The ground is a faint tint: near white in light mode, near black in dark mode")
    func ground() {
        for flavor in Self.colours {
            #expect(flavor.ground(dark: false).luminance > 0.8, "\(flavor.hex) light ground is too dark")
            #expect(flavor.ground(dark: true).luminance < 0.03, "\(flavor.hex) dark ground is too light")
        }
    }

    @Test("Cards stand apart from the ground in both modes")
    func surface() {
        for flavor in Self.colours {
            for dark in [false, true] {
                #expect(Flavor.contrast(flavor.surface(dark: dark), flavor.ground(dark: dark)) > 1.08,
                        "\(flavor.hex) \(dark ? "dark" : "light") cards vanish into the ground")
            }
        }
    }

    @Test("The accent reads on the ground and on cards at 3:1, whatever the base colour")
    func accentReadable() {
        for flavor in Self.colours {
            for dark in [false, true] {
                let accent = flavor.accent(dark: dark)
                #expect(Flavor.contrast(accent, flavor.ground(dark: dark)) >= 3, "\(flavor.hex) \(dark) on ground")
                #expect(Flavor.contrast(accent, flavor.surface(dark: dark)) >= 3, "\(flavor.hex) \(dark) on cards")
            }
        }
    }

    @Test("A base colour that already reads is kept as it is")
    func accentKept() throws {
        let navy = try #require(Flavor(hex: "#0F3D6E"))
        #expect(navy.accent(dark: false) == navy.base)
    }

    @Test("Text on the accent is black or white, whichever reads better, at 3:1 or more")
    func onAccent() {
        for flavor in Self.colours {
            for dark in [false, true] {
                let accent = flavor.accent(dark: dark)
                let text = flavor.onAccent(dark: dark)
                #expect(text == .white || text == .black)
                #expect(Flavor.contrast(text, accent) >= 3, "\(flavor.hex) \(dark)")
                let other: Flavor.RGB = text == .white ? .black : .white
                #expect(Flavor.contrast(text, accent) >= Flavor.contrast(other, accent))
            }
        }
    }

    @Test("Swatches are distinct and named")
    func swatches() {
        #expect(Set(Flavor.swatches.map(\.flavor.hex)).count == Flavor.swatches.count)
        #expect(Flavor.swatches.count >= 10)
    }

    @Test("Round-trips through JSON, Main as hex")
    func codable() throws {
        let flavor = try #require(Flavor(hex: "#C2566F"))
        let data = try JSONEncoder().encode(flavor)
        #expect(String(data: data, encoding: .utf8)?.contains("#C2566F") == true)
        #expect(try JSONDecoder().decode(Flavor.self, from: data) == flavor)
    }
}

import SwiftUI

/// One base colour that becomes the whole page: a faint ground, cards that
/// stand apart from it, an accent that stays readable on both, and black or
/// white text on the accent.
///
/// The idea is Aether's Flavor (github.com/Aeastr/FlavorPlayground), with the
/// contrast rules of Garnish (github.com/Aeastr/Garnish): WCAG luminance and
/// contrast ratios. Unlike the playground, every step is deterministic, so a
/// colour always gives the same page.
nonisolated struct Flavor: Equatable, Hashable, Sendable {
    /// A colour in sRGB, components from 0 to 1.
    nonisolated struct RGB: Equatable, Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        static let white = RGB(red: 1, green: 1, blue: 1)
        static let black = RGB(red: 0, green: 0, blue: 0)

        /// WCAG 2.1 relative luminance.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red.clamped(to: 0...1)
            self.green = green.clamped(to: 0...1)
            self.blue = blue.clamped(to: 0...1)
        }

        init(hue: Double, saturation: Double, brightness: Double) {
            let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
            let s = saturation.clamped(to: 0...1), v = brightness.clamped(to: 0...1)
            let sector = Int(h) % 6, fraction = h - Double(Int(h))
            let p = v * (1 - s), q = v * (1 - s * fraction), t = v * (1 - s * (1 - fraction))
            switch sector {
            case 0: self.init(red: v, green: t, blue: p)
            case 1: self.init(red: q, green: v, blue: p)
            case 2: self.init(red: p, green: v, blue: t)
            case 3: self.init(red: p, green: q, blue: v)
            case 4: self.init(red: t, green: p, blue: v)
            default: self.init(red: v, green: p, blue: q)
            }
        }

        var hsb: (hue: Double, saturation: Double, brightness: Double) {
            let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
            var hue = 0.0
            if delta > 0 {
                if high == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
                else if high == green { hue = (blue - red) / delta + 2 }
                else { hue = (red - green) / delta + 4 }
                hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
            }
            return (hue, high == 0 ? 0 : delta / high, high)
        }

        @MainActor var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    }

    var base: RGB

    init(red: Double, green: Double, blue: Double) {
        base = RGB(red: red, green: green, blue: blue)
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((base.red * 255).rounded()), Int((base.green * 255).rounded()),
               Int((base.blue * 255).rounded()))
    }

    /// WCAG contrast ratio, from 1 to 21, whichever colour is lighter.
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let a = first.luminance, b = second.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Large text and symbols: WCAG's threshold for them.
    static let readable = 3.0

    // MARK: Palette

    /// The page behind everything: a whisper of the colour.
    func ground(dark: Bool) -> RGB {
        let (hue, saturation, _) = base.hsb
        return dark
            ? RGB(hue: hue, saturation: saturation * 0.35, brightness: 0.11)
            : RGB(hue: hue, saturation: min(saturation * 0.06, 0.06), brightness: 0.98)
    }

    /// A solid card on that ground.
    func surface(dark: Bool) -> RGB {
        let (hue, saturation, _) = base.hsb
        return dark
            ? RGB(hue: hue, saturation: saturation * 0.3, brightness: 0.2)
            : RGB(hue: hue, saturation: min(saturation * 0.16, 0.14), brightness: 0.9)
    }

    /// The colour itself where it reads on the ground and on cards;
    /// otherwise the same hue darkened (light mode) or lightened and then
    /// washed out (dark mode) until it does.
    func accent(dark: Bool) -> RGB {
        let backgrounds = [ground(dark: dark), surface(dark: dark)]
        func reads(_ colour: RGB) -> Bool {
            backgrounds.allSatisfy { Flavor.contrast(colour, $0) >= Flavor.readable }
        }
        guard !reads(base) else { return base }
        var (hue, saturation, brightness) = base.hsb
        for _ in 0..<60 {
            if dark {
                if brightness < 1 { brightness = min(brightness + 0.04, 1) } else { saturation = max(saturation - 0.05, 0) }
            } else {
                brightness = max(brightness - 0.04, 0)
            }
            let candidate = RGB(hue: hue, saturation: saturation, brightness: brightness)
            if reads(candidate) { return candidate }
        }
        return dark ? .white : .black
    }

    /// Black or white, whichever reads better on the accent.
    func onAccent(dark: Bool) -> RGB {
        let accent = accent(dark: dark)
        return Flavor.contrast(.white, accent) >= Flavor.contrast(.black, accent) ? .white : .black
    }

    // MARK: Swatches

    struct Swatch: Identifiable, Sendable {
        let name: LocalizedStringResource
        let flavor: Flavor
        var id: String { flavor.hex }
    }

    static let polimi = Flavor(hex: "#0F3D6E")!

    /// A starting set; any other colour comes from the picker.
    static let swatches: [Swatch] = [
        Swatch(name: "Blu Politecnico", flavor: polimi),
        Swatch(name: "Lavanda", flavor: Flavor(hex: "#7A6FE0")!),
        Swatch(name: "Indaco", flavor: Flavor(hex: "#3B4BC8")!),
        Swatch(name: "Cielo", flavor: Flavor(hex: "#2E9BD6")!),
        Swatch(name: "Menta", flavor: Flavor(hex: "#2FA88A")!),
        Swatch(name: "Salvia", flavor: Flavor(hex: "#5E8C61")!),
        Swatch(name: "Mandarino", flavor: Flavor(hex: "#E8751A")!),
        Swatch(name: "Corallo", flavor: Flavor(hex: "#E0584F")!),
        Swatch(name: "Lampone", flavor: Flavor(hex: "#C2386F")!),
        Swatch(name: "Caffè", flavor: Flavor(hex: "#8A5A3C")!),
        Swatch(name: "Ardesia", flavor: Flavor(hex: "#5B6472")!),
        Swatch(name: "Grafite", flavor: Flavor(hex: "#1F2328")!),
    ]
}

/// Stored as its hex string: short, and readable in the defaults.
nonisolated extension Flavor: Codable {
    init(from decoder: any Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let flavor = Flavor(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a hex colour: \(hex)"))
        }
        self = flavor
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

extension Flavor {
    /// The palette in the current colour scheme, as SwiftUI colours.
    struct Palette {
        let ground: Color
        let surface: Color
        let accent: Color
        let onAccent: Color
    }

    func palette(_ scheme: ColorScheme) -> Palette {
        let dark = scheme == .dark
        return Palette(ground: ground(dark: dark).color, surface: surface(dark: dark).color,
                       accent: accent(dark: dark).color, onAccent: onAccent(dark: dark).color)
    }
}

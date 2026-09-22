import SwiftUI

/// Three colours that become the whole app: a faint ground, cards that stand
/// apart from it, accents that stay readable on both, and black or white text
/// on the accent.
///
/// Main is the look's colour; Accent and Extra are neighbouring hues derived
/// from it, unless set by hand or taken from a photo. The idea is Aether's
/// Flavor (github.com/Aeastr/FlavorPlayground) with the contrast rules of
/// Garnish (github.com/Aeastr/Garnish): WCAG luminance and contrast ratios.
/// Unlike the playground, every step is deterministic, so the same colours
/// always give the same app.
nonisolated struct Flavor: Equatable, Hashable, Sendable {
    /// A colour in sRGB, components from 0 to 1.
    nonisolated struct RGB: Equatable, Hashable, Sendable {
        /// The red channel, 0 to 1.
        var red: Double
        /// The green channel, 0 to 1.
        var green: Double
        /// The blue channel, 0 to 1.
        var blue: Double

        /// Pure white.
        static let white = RGB(red: 1, green: 1, blue: 1)
        /// Pure black.
        static let black = RGB(red: 0, green: 0, blue: 0)

        /// WCAG 2.1 relative luminance.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        /// A colour from its channels, each clamped to 0…1.
        ///
        /// - Parameters:
        ///   - red: The red channel.
        ///   - green: The green channel.
        ///   - blue: The blue channel.
        init(red: Double, green: Double, blue: Double) {
            self.red = red.clamped(to: 0...1)
            self.green = green.clamped(to: 0...1)
            self.blue = blue.clamped(to: 0...1)
        }

        /// A colour from hue, saturation and brightness.
        ///
        /// - Parameters:
        ///   - hue: The hue, 0 to 1, wrapping around the wheel.
        ///   - saturation: How much colour, 0 to 1.
        ///   - brightness: How light, 0 to 1.
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

        /// A colour from a six-digit hex string, with or without the leading hash.
        ///
        /// - Parameter hex: The string.
        /// - Returns: `nil` when it is not six hex digits.
        init?(hex: String) {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
            self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255)
        }

        /// The colour as `#RRGGBB`.
        var hex: String {
            String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }

        /// The colour as hue, saturation and brightness.
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

        /// The colour as SwiftUI draws it.
        @MainActor var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    }

    /// The three colours a Flavor is made of.
    nonisolated enum Role: String, CaseIterable, Sendable {
        /// Main is the look's colour; Accent and Extra follow from it unless set by hand.
        case main, accent, extra
    }

    /// How strongly the Flavor colours the page: the standard whisper, pure
    /// white or black for contrast, or a clearly tinted page.
    nonisolated enum Mode: String, CaseIterable, Sendable {
        /// A standard whisper of colour on the page, pure white or black for contrast, or a clearly tinted page.
        case standard, contrast, tinted
    }

    /// Main, the look's colour.
    var base: RGB
    /// Accent as the student set it, or `nil` to derive it from Main.
    private var accentOverride: RGB?
    /// Extra as the student set it, or `nil` to derive it from Main.
    private var extraOverride: RGB?

    /// A Flavor from Main's channels, with Accent and Extra derived.
    ///
    /// - Parameters:
    ///   - red: Main's red channel.
    ///   - green: Main's green channel.
    ///   - blue: Main's blue channel.
    init(red: Double, green: Double, blue: Double) {
        base = RGB(red: red, green: green, blue: blue)
    }

    /// A Flavor from its colours.
    ///
    /// - Parameters:
    ///   - main: The look's colour.
    ///   - accent: Accent, or `nil` to derive it.
    ///   - extra: Extra, or `nil` to derive it.
    init(main: RGB, accent: RGB? = nil, extra: RGB? = nil) {
        base = main
        accentOverride = accent
        extraOverride = extra
    }

    /// A Flavor from Main as a hex string, with Accent and Extra derived.
    ///
    /// - Parameter hex: The string.
    /// - Returns: `nil` when it is not a hex colour.
    init?(hex: String) {
        guard let main = RGB(hex: hex) else { return nil }
        self.init(main: main)
    }

    /// The look's colour.
    var main: RGB { base }
    /// Main as `#RRGGBB`.
    var hex: String { base.hex }

    /// A neighbouring, deeper hue, unless set by hand.
    var accentColour: RGB {
        get { accentOverride ?? derived(hueShift: -0.08, saturation: 0.9, brightness: 0.85) }
        set { accentOverride = newValue }
    }

    /// A further, darker hue, unless set by hand.
    var extraColour: RGB {
        get { extraOverride ?? derived(hueShift: -0.18, saturation: 0.95, brightness: 0.7) }
        set { extraOverride = newValue }
    }

    /// Accent and Extra back to the ones Main suggests.
    mutating func resetDerived() {
        accentOverride = nil
        extraOverride = nil
    }

    /// A colour a step around the wheel from Main.
    ///
    /// - Parameters:
    ///   - hueShift: How far to turn, in fractions of the wheel.
    ///   - saturation: What to multiply Main's saturation by.
    ///   - brightness: What to multiply Main's brightness by.
    /// - Returns: The colour, deepened only when Main is a grey with no hue to move along.
    private func derived(hueShift: Double, saturation: Double, brightness: Double) -> RGB {
        let (hue, s, b) = base.hsb
        // A grey has no hue to move along: it only deepens.
        guard s >= 0.12 else { return RGB(hue: hue, saturation: s, brightness: b * brightness) }
        return RGB(hue: hue + hueShift, saturation: s * saturation, brightness: max(b * brightness, 0.25))
    }

    /// One of the Flavor's three colours.
    ///
    /// - Parameter role: Which one.
    /// - Returns: The colour.
    func colour(_ role: Role) -> RGB {
        switch role {
        case .main: main
        case .accent: accentColour
        case .extra: extraColour
        }
    }

    /// WCAG contrast ratio, from 1 to 21, whichever colour is lighter.
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let a = first.luminance, b = second.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Large text and symbols: WCAG's threshold for them.
    static let readable = 3.0

    // MARK: Palette

    /// The page behind everything.
    func ground(dark: Bool, mode: Mode = .standard) -> RGB {
        let (hue, saturation, _) = base.hsb
        switch (mode, dark) {
        case (.standard, false): return RGB(hue: hue, saturation: min(saturation * 0.06, 0.06), brightness: 0.98)
        case (.standard, true): return RGB(hue: hue, saturation: saturation * 0.35, brightness: 0.11)
        case (.contrast, false): return .white
        case (.contrast, true): return .black
        case (.tinted, false): return RGB(hue: hue, saturation: min(saturation * 0.18, 0.16), brightness: 0.95)
        case (.tinted, true): return RGB(hue: hue, saturation: saturation * 0.5, brightness: 0.14)
        }
    }

    /// A solid card on that ground.
    func surface(dark: Bool, mode: Mode = .standard) -> RGB {
        let (hue, saturation, _) = base.hsb
        switch (mode, dark) {
        case (.standard, false): return RGB(hue: hue, saturation: min(saturation * 0.16, 0.14), brightness: 0.9)
        case (.standard, true): return RGB(hue: hue, saturation: saturation * 0.3, brightness: 0.2)
        case (.contrast, false): return RGB(hue: hue, saturation: min(saturation * 0.05, 0.04), brightness: 0.93)
        case (.contrast, true): return RGB(hue: hue, saturation: saturation * 0.15, brightness: 0.16)
        case (.tinted, false): return RGB(hue: hue, saturation: min(saturation * 0.3, 0.26), brightness: 0.87)
        case (.tinted, true): return RGB(hue: hue, saturation: saturation * 0.45, brightness: 0.24)
        }
    }

    /// A role's colour where it reads on the ground and on cards; otherwise
    /// the same hue darkened (light) or lightened and then washed out (dark)
    /// until it does.
    func readable(_ role: Role, dark: Bool, mode: Mode = .standard) -> RGB {
        let backgrounds = [ground(dark: dark, mode: mode), surface(dark: dark, mode: mode)]
        func reads(_ colour: RGB) -> Bool {
            backgrounds.allSatisfy { Flavor.contrast(colour, $0) >= Flavor.readable }
        }
        let start = colour(role)
        guard !reads(start) else { return start }
        var (hue, saturation, brightness) = start.hsb
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

    /// Main, readable: the accent of the app.
    func accent(dark: Bool, mode: Mode = .standard) -> RGB {
        readable(.main, dark: dark, mode: mode)
    }

    /// Black or white, whichever reads better on the accent.
    func onAccent(dark: Bool, mode: Mode = .standard) -> RGB {
        let accent = accent(dark: dark, mode: mode)
        return Flavor.contrast(.white, accent) >= Flavor.contrast(.black, accent) ? .white : .black
    }

    // MARK: Name

    /// A playful name from Main's hue, the way Kyo names its flavours.
    var name: String {
        let (hue, saturation, brightness) = base.hsb
        if saturation < 0.12 { return brightness > 0.75 ? "Nuvolaaa" : "Grafiteee" }
        let names = ["Fragolaaa", "Tostatooo", "Solaaare", "Limeee", "Frescooo", "Mentaaa",
                     "Cielooo", "Bluuu", "Notteee", "Lavandaaa", "Lamponeee", "Rosaaa"]
        // Twelve hue slices, the first centred on red.
        let slice = Int(((hue + 1 / 24).truncatingRemainder(dividingBy: 1)) * 12) % 12
        return names[slice]
    }

    // MARK: Sharing

    /// The scheme a share code begins with, so a pasted string can be recognised.
    private static let sharePrefix = "poliverse-flavor:"

    /// A short code carrying the three colours, to send to a friend.
    var shareCode: String {
        Self.sharePrefix + [main, accentColour, extraColour].map(\.hex).joined(separator: ",")
    }

    /// A Flavor from a share code: Main alone, or all three colours.
    init?(shareCode: String) {
        let code = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(Self.sharePrefix) else { return nil }
        let colours = code.dropFirst(Self.sharePrefix.count).split(separator: ",").map { RGB(hex: String($0)) }
        guard !colours.isEmpty, colours.allSatisfy({ $0 != nil }) else { return nil }
        switch colours.count {
        case 1: self.init(main: colours[0]!)
        case 3: self.init(main: colours[0]!, accent: colours[1], extra: colours[2])
        default: return nil
        }
    }

    // MARK: From a photo

    /// The three most present vivid hues of a photo's pixels, most present
    /// first; a mostly grey photo gives its average grey. Nil without pixels.
    static func extract(from pixels: [RGB]) -> Flavor? {
        guard !pixels.isEmpty else { return nil }
        let vivid = pixels.filter { let hsb = $0.hsb; return hsb.saturation >= 0.25 && hsb.brightness >= 0.2 }
        guard vivid.count * 20 >= pixels.count else {
            return Flavor(main: average(pixels))
        }
        // Thirty-six hue bins; each keeps its pixels to average later.
        var bins = [[RGB]](repeating: [], count: 36)
        for pixel in vivid {
            bins[min(Int(pixel.hsb.hue * 36), 35)].append(pixel)
        }
        var chosen: [RGB] = []
        for bin in bins.indices.sorted(by: { bins[$0].count > bins[$1].count }) where !bins[bin].isEmpty {
            let colour = average(bins[bin])
            let distinct = chosen.allSatisfy { other in
                let d = abs(other.hsb.hue - colour.hsb.hue)
                return min(d, 1 - d) >= 0.06
            }
            if distinct { chosen.append(colour) }
            if chosen.count == 3 { break }
        }
        return Flavor(main: chosen[0], accent: chosen.count > 1 ? chosen[1] : nil, extra: chosen.count > 2 ? chosen[2] : nil)
    }

    /// The mean of some colours, channel by channel.
    ///
    /// - Parameter colours: The colours, at least one.
    /// - Returns: Their average.
    private static func average(_ colours: [RGB]) -> RGB {
        let count = Double(colours.count)
        return RGB(red: colours.map(\.red).reduce(0, +) / count, green: colours.map(\.green).reduce(0, +) / count,
                   blue: colours.map(\.blue).reduce(0, +) / count)
    }

    // MARK: Swatches

    /// A named Flavor offered in the picker.
    struct Swatch: Identifiable, Sendable {
        /// What the swatch is called.
        let name: LocalizedStringResource
        /// The Flavor it stands for.
        let flavor: Flavor
        /// The swatch's identity, which is Main's hex.
        var id: String { flavor.hex }
    }

    /// The Politecnico's own navy, which the app opens on.
    static let polimi = Flavor(hex: "#0F3D6E")!

    /// A starting set; any other colour comes from the picker or a photo.
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

/// Stored as its three colours; a plain hex string from before is Main alone.
nonisolated extension Flavor: Codable {
    /// The three colours as they are stored.
    private enum CodingKeys: String, CodingKey {
        case main, accent, extra
    }

    /// Reads a Flavor, accepting a bare hex string as Main alone.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: ``DecodingError`` when a colour is not a hex string.
    init(from decoder: any Decoder) throws {
        if let hex = try? decoder.singleValueContainer().decode(String.self) {
            guard let main = RGB(hex: hex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a hex colour: \(hex)"))
            }
            self.init(main: main)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let main = RGB(hex: try container.decode(String.self, forKey: .main)) else {
            throw DecodingError.dataCorruptedError(forKey: .main, in: container, debugDescription: "Not a hex colour")
        }
        self.init(main: main,
                  accent: try container.decodeIfPresent(String.self, forKey: .accent).flatMap(RGB.init(hex:)),
                  extra: try container.decodeIfPresent(String.self, forKey: .extra).flatMap(RGB.init(hex:)))
    }

    /// Writes Main, and Accent and Extra only where they were set by hand.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(main.hex, forKey: .main)
        try container.encodeIfPresent(accentOverride?.hex, forKey: .accent)
        try container.encodeIfPresent(extraOverride?.hex, forKey: .extra)
    }
}

/// The Flavor resolved for a colour scheme, as SwiftUI colours.
extension Flavor {
    /// The palette in a colour scheme and mode, as SwiftUI colours.
    struct Palette {
        /// The page behind everything.
        let ground: Color
        /// A card on that page.
        let surface: Color
        /// The colour for controls and marks.
        let accent: Color
        /// Accent made readable as text on the page.
        let accentSecondary: Color
        /// Extra made readable as text on the page.
        let extra: Color
        /// Black or white, whichever reads on ``accent``.
        let onAccent: Color
        /// The raw colours, for gradients and tiles where legibility is not at stake.
        let mainRaw: Color
        /// Accent as it was chosen.
        let accentRaw: Color
        /// Extra as it was chosen.
        let extraRaw: Color
    }

    /// The Flavor resolved for one appearance.
    ///
    /// - Parameters:
    ///   - scheme: Light or dark.
    ///   - mode: How strongly the Flavor colours the page.
    /// - Returns: The palette.
    func palette(_ scheme: ColorScheme, mode: Mode = .standard) -> Palette {
        let dark = scheme == .dark
        return Palette(ground: ground(dark: dark, mode: mode).color, surface: surface(dark: dark, mode: mode).color,
                       accent: accent(dark: dark, mode: mode).color,
                       accentSecondary: readable(.accent, dark: dark, mode: mode).color,
                       extra: readable(.extra, dark: dark, mode: mode).color,
                       onAccent: onAccent(dark: dark, mode: mode).color,
                       mainRaw: main.color, accentRaw: accentColour.color, extraRaw: extraColour.color)
    }
}

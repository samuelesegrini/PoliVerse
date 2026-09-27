import SwiftUI

/// What comes up over Personalizza's editor in a sheet of its own: a
/// section's card, whose forms are cards to swipe through, or the sticker
/// keyboard.
enum CustomizePage: Hashable, Identifiable {
    /// One section of Oggi, with its form and surface.
    case section(TodaySection.Kind)
    /// The emoji keyboard, to add stickers.
    case stickerPicker

    /// The sheet's identity, which names the section it belongs to where there is one.
    var id: String {
        switch self {
        case .section(let kind): "section-\(kind.rawValue)"
        case .stickerPicker: "stickerPicker"
        }
    }

    /// What the sheet is called in its navigation bar.
    var title: LocalizedStringKey {
        switch self {
        case .section(let kind): kind.title
        case .stickerPicker: "Aggiungi sticker"
        }
    }
}

extension View {
    /// A panel page's title: inline, as a sheet this low has room for, but a
    /// step larger than the system's, so each part of the look reads as a
    /// place of its own. The navigation title stays for the back button.
    ///
    /// - Parameter title: The page's name.
    /// - Returns: The page with its title.
    func panelTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

/// A material on the look's background, with a line of text and an accent.
struct MaterialPreview: View {
    /// The material to draw.
    let material: TodayMaterial
    /// The look, which supplies the background and the accent.
    let style: TodayStyle
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        TodayBackgroundView(style: style)
            .overlay {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(style.accent(scheme)).frame(width: 18, height: 4)
                    Capsule().fill(.primary.opacity(0.6)).frame(width: 26, height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(7)
                .todayMaterial(material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: 9)
                .padding(8)
            }
            .clipShape(.rect(cornerRadius: 14))
    }
}

/// Reading a photo's colours, to take a Flavor from it.
extension UIImage {
    /// A small grid of the image's colours, for picking a Flavor from it.
    func samplePixels(side: Int = 40) -> [Flavor.RGB] {
        guard let cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).compactMap { index in
            guard bytes[index + 3] > 128 else { return nil }
            return Flavor.RGB(red: Double(bytes[index]) / 255, green: Double(bytes[index + 1]) / 255,
                              blue: Double(bytes[index + 2]) / 255)
        }
    }

    /// A JPEG no larger than a side, for photos kept beside the date.
    func resizedJPEG(maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).jpegData(withCompressionQuality: 0.85) { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

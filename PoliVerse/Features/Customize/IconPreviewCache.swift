import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The app icon previews Personalizza shows, decoded off the main thread and
/// kept once decoded.
///
/// The icon part draws a dozen or more 180-pixel pictures from the asset
/// catalog the moment it opens. Left to `Image(name)`, each is looked up and
/// decoded on the main thread as it first draws, and on a first open that
/// froze Personalizza. Here each is decoded and scaled to the size it is drawn
/// at on a background task, then kept, so the next time the part opens the
/// pictures are simply there.
final class IconPreviewCache {
    /// The one cache, shared by every picker.
    static let shared = IconPreviewCache()

    /// The pictures decoded so far, by ``key(_:pixelSide:)``.
    private var images: [String: Image] = [:]
    /// The pictures being decoded, so two tiles asking for one decode it once.
    private var loading: [String: Task<DecodedPreview?, Never>] = [:]

    /// The key a picture is kept under: its name and the size it was decoded at.
    private func key(_ name: String, pixelSide: Int) -> String { "\(name)@\(pixelSide)" }

    /// A picture already decoded, without waiting.
    ///
    /// - Parameters:
    ///   - name: The asset's name.
    ///   - pixelSide: The side it is drawn at, in pixels.
    /// - Returns: The picture, or `nil` until it has been decoded.
    func cached(_ name: String, pixelSide: Int) -> Image? {
        images[key(name, pixelSide: pixelSide)]
    }

    /// A picture, decoded in the background the first time it is asked for.
    ///
    /// - Parameters:
    ///   - name: The asset's name.
    ///   - pixelSide: The side it is drawn at, in pixels.
    /// - Returns: The picture, or `nil` when the catalog has no such asset.
    @discardableResult
    func image(named name: String, pixelSide: Int) async -> Image? {
        let key = key(name, pixelSide: pixelSide)
        if let image = images[key] { return image }
        let task = loading[key] ?? Task.detached(priority: .userInitiated) {
            Self.decode(name, pixelSide: pixelSide)
        }
        loading[key] = task
        let decoded = await task.value
        loading[key] = nil
        guard let decoded else { return nil }
        let image = Image(decorative: decoded.image, scale: 1)
        images[key] = image
        return image
    }

    /// Decodes several pictures one after another, for the ones a row has not
    /// scrolled to yet.
    ///
    /// - Parameters:
    ///   - names: The assets' names.
    ///   - pixelSide: The side they are drawn at, in pixels.
    func prefetch(_ names: [String], pixelSide: Int) async {
        for name in names {
            guard !Task.isCancelled else { return }
            await image(named: name, pixelSide: pixelSide)
        }
    }

    /// Looks a picture up and draws it into a bitmap of the size it is shown
    /// at: the decode happens here rather than at first draw, and a 52-point
    /// tile does not carry the 180-pixel original.
    ///
    /// - Parameters:
    ///   - name: The asset's name.
    ///   - pixelSide: The side to draw it at, in pixels.
    /// - Returns: The decoded picture, or `nil` when there is no such asset.
    nonisolated private static func decode(_ name: String, pixelSide: Int) -> DecodedPreview? {
        #if os(iOS)
        guard let source = UIImage(named: name)?.cgImage else { return nil }
        #else
        guard let source = NSImage(named: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        #endif
        let side = max(1, min(pixelSide, max(source.width, source.height)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage().map(DecodedPreview.init)
    }
}

/// A decoded picture handed from the background task to the main thread. A
/// `CGImage` is immutable once made, so passing it across is safe.
nonisolated private struct DecodedPreview: @unchecked Sendable {
    /// The bitmap.
    let image: CGImage
}

/// An icon preview that appears when decoded, over a quiet placeholder until then.
struct IconPreviewImage: View {
    /// The asset's name.
    let name: String
    /// The side it is drawn at, in points.
    var side: CGFloat = 52
    /// The corner radius of the tile.
    var cornerRadius: CGFloat = 12

    /// Points to pixels on this screen.
    @Environment(\.displayScale) private var displayScale
    /// The picture this view decoded, with the name it was decoded for: a
    /// tile whose name changes shows the cache's copy of the new one, never
    /// the old picture.
    @State private var loaded: (name: String, image: Image)?

    /// The side to decode at, in pixels.
    private var pixelSide: Int { Int((side * displayScale).rounded(.up)) }

    /// The view's content.
    var body: some View {
        let image = loaded?.name == name ? loaded?.image : IconPreviewCache.shared.cached(name, pixelSide: pixelSide)
        let tile = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            tile.fill(.white.opacity(0.08))
            if let image {
                image
                    .resizable()
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(tile)
        .animation(.easeOut(duration: 0.15), value: image == nil)
        .task(id: name) {
            guard let image = await IconPreviewCache.shared.image(named: name, pixelSide: pixelSide) else { return }
            loaded = (name, image)
        }
    }
}

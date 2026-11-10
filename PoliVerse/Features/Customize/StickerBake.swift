import SwiftUI

/// A sticker with its white cut-out edge and soft shadow drawn once into a
/// bitmap, rather than by the `stickerOutline` layer effect on every frame.
///
/// The layer effect takes 32 samples per pixel and draws the sticker offscreen
/// first; on a page that scrolls it ran for every sticker on every frame. Baked,
/// the sticker is one image. Only for stickers that hold still: one being moved,
/// pinched or turned in the editor keeps the live effect, since its size changes
/// with every frame. `-TodayLegacy stickerEdge` turns the bake off.
struct BakedSticker: View {
    /// What the sticker is.
    let content: PlacedSticker.Content
    /// The sticker's side, in points.
    let side: CGFloat
    /// How wide the white edge is, in points, as ``SwiftUI/View/stickerOutline(_:radius:)`` draws it.
    var radius: CGFloat = 5

    /// The screen's pixels per point, which the bitmap is drawn at.
    @Environment(\.displayScale) private var scale
    /// The bitmap, with the size it was baked for.
    @State private var baked: (key: StickerBake.Key, image: CGImage)?

    /// The view's content.
    var body: some View {
        let key = StickerBake.Key(content: content, side: Int(side.rounded()), scale: scale)
        ZStack {
            if let image = StickerBake.cached(key) ?? (baked?.key == key ? baked?.image : nil) {
                let full = side + 2 * StickerBake.margin(radius: radius)
                Image(decorative: image, scale: scale)
                    .resizable()
                    .frame(width: full, height: full)
                    // Laid out at the sticker's own side; the edge and the
                    // shadow spill over it, as the live effect's do.
                    .frame(width: side, height: side)
            } else {
                // Until the bitmap is ready: the live edge, as before.
                StickerContentView(content: content)
                    .frame(width: side, height: side)
                    .stickerOutline(true, radius: radius)
            }
        }
        .task(id: key) {
            guard StickerBake.cached(key) == nil else { return }
            if let image = await StickerBake.bake(key, radius: radius) {
                baked = (key, image)
            }
        }
    }
}

/// Bakes and keeps sticker bitmaps for ``BakedSticker``.
enum StickerBake {
    /// What a bitmap was baked for: the sticker, its side in points and the screen's scale.
    struct Key: Hashable {
        let content: PlacedSticker.Content
        let side: Int
        let scale: CGFloat
    }

    /// Baked bitmaps. A page holds a handful of stickers; the whole set is
    /// dropped past 32, which only the editor's resizing reaches.
    private static var cache: [Key: CGImage] = [:]

    /// The room around the sticker the edge and the shadow need, in points.
    static func margin(radius: CGFloat) -> CGFloat { radius + 6 }

    /// The bitmap baked for `key` already, if any.
    static func cached(_ key: Key) -> CGImage? { cache[key] }

    /// Draws the sticker with its edge and shadow into a bitmap, and keeps it.
    ///
    /// The edge is the layer effect's own method done once: the sticker's
    /// silhouette in white, stamped at 16 angles on two rings out to `radius`,
    /// under the sticker itself; the shadow is cast by the whole.
    ///
    /// - Parameters:
    ///   - key: The sticker, its side and the screen's scale.
    ///   - radius: How wide the white edge is, in points.
    /// - Returns: The bitmap, `margin(radius:)` larger than the sticker on every side.
    static func bake(_ key: Key, radius: CGFloat) async -> CGImage? {
        if let hit = cache[key] { return hit }
        // A stored sticker is read and decoded first, so the renderer below
        // draws the picture rather than the empty frame shown while it loads.
        if case .image(let id) = key.content, await StickerImages.load(id) == nil { return nil }

        let side = CGFloat(key.side)
        let renderer = ImageRenderer(content: StickerContentView(content: key.content)
            .frame(width: side, height: side))
        renderer.scale = key.scale
        guard let base = renderer.cgImage,
              let image = outlined(base, edge: radius * key.scale,
                                   margin: margin(radius: radius) * key.scale, scale: key.scale)
        else { return nil }
        if cache.count >= 32 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// The edge and the shadow around `base`, in pixels.
    private static func outlined(_ base: CGImage, edge: CGFloat, margin: CGFloat, scale: CGFloat) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)

        // The sticker's shape in white.
        guard let mask = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        mask.draw(base, in: bounds)
        mask.setBlendMode(.sourceIn)
        mask.setFillColor(CGColor(gray: 1, alpha: 1))
        mask.fill(bounds)
        guard let silhouette = mask.makeImage() else { return nil }

        let pad = margin.rounded(.up)
        guard let canvas = CGContext(data: nil, width: base.width + Int(2 * pad), height: base.height + Int(2 * pad),
                                     bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        else { return nil }
        let at = bounds.offsetBy(dx: pad, dy: pad)
        // The live effect's shadow: black at 18%, radius 4, 2 points down
        // (a bitmap's y runs up).
        canvas.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 4 * scale,
                         color: CGColor(gray: 0, alpha: 0.18))
        canvas.beginTransparencyLayer(auxiliaryInfo: nil)
        for ring in 1...2 {
            let distance = edge * CGFloat(ring) / 2
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                canvas.draw(silhouette, in: at.offsetBy(dx: cos(angle) * distance, dy: sin(angle) * distance))
            }
        }
        canvas.draw(base, in: at)
        canvas.endTransparencyLayer()
        return canvas.makeImage()
    }
}

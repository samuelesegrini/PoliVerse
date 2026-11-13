#if DEBUG && os(iOS)
import Metal
import OSLog
import RealityKit
import UIKit

/// A still of a building in the app's own 3D campus, for the room card's Mappa picture: the
/// same scene the new map draws (``Trifoglio3DScene``), seen from the south-west and above as
/// the map flies to a building, with the building's roof in the middle of the picture where
/// the card puts the room's pin.
///
/// Drawn offscreen with `RealityRenderer`, never in a view, and kept on disk by building and
/// look: the campus is read (about 50 MB of USDZ) only the first time a building is shown,
/// and every later card of that building, in this launch or the next, reads a PNG of a few
/// hundred kilobytes. The campus is let go as soon as the stills asked for are drawn.
@MainActor
enum RoomCampusStill {
    /// The size the still is drawn at, in points: wider and taller than the card's picture,
    /// so it can be cropped from its centre to the hero and to the thumbnail.
    static let size = CGSize(width: 440, height: 260)
    /// Pixels per point.
    private static let scale: CGFloat = 3
    /// The camera's angle from vertical and its side, as the map's flights to a building.
    private static let polar: Float = 0.95
    private static let azimuth: Float = -.pi / 4
    private static let fieldOfView: Float = 35

    private static var memory: [String: UIImage] = [:]
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "room-still")

    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "RoomCampusStills", directoryHint: .isDirectory)
    }

    /// Whether a building is in the 3D campus, so it can have a still.
    static func canDraw(_ buildingCode: String) -> Bool {
        Trifoglio3DScene.buildings.contains(buildingCode)
    }

    /// The still of a building, from memory, from disk, or drawn now.
    ///
    /// - Parameters:
    ///   - buildingCode: The building's `csie`.
    ///   - dark: Whether to draw it in the night palette.
    /// - Returns: The still, or `nil` when the building is not in the campus or it cannot be drawn.
    static func image(for buildingCode: String, dark: Bool) async -> UIImage? {
        guard canDraw(buildingCode) else { return nil }
        let key = "\(buildingCode)-\(dark ? "notte" : "giorno")"
        if let image = memory[key] { return image }
        let file = folder?.appending(path: "\(key).png")
        if let file, let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
            memory[key] = image
            return image
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task<UIImage?, Never> { await draw(buildingCode, dark: dark) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        guard let image else { return nil }
        memory[key] = image
        if let folder, let file, let data = image.pngData() {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    /// Reads the campus into a scene of its own, frames the building and draws one frame.
    private static func draw(_ buildingCode: String, dark: Bool) async -> UIImage? {
        let started = ContinuousClock.now
        let scene = Trifoglio3DScene()
        scene.dark = dark
        guard let root = await scene.loadForStill(),
              let shell = root.findEntity(named: "Edifici")?.children.first(where: { $0.name == buildingCode })
        else {
            log.error("still: \(buildingCode, privacy: .public) not in the campus")
            return nil
        }
        let box = shell.visualBounds(relativeTo: nil)
        guard !box.isEmpty else { return nil }

        // The roof's centre in the middle of the picture, the building with a little of its
        // neighbours around it.
        let target = SIMD3<Float>(box.center.x, box.max.y, box.center.z)
        let radius = max(length(box.extents) / 2, 12) * 1.05
        let distance = radius / sin(fieldOfView * .pi / 180 / 2)
        let offset = SIMD3<Float>(sin(polar) * sin(azimuth), cos(polar), sin(polar) * cos(azimuth)) * distance
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = fieldOfView
        camera.camera.near = 1
        camera.camera.far = 4000
        camera.look(at: target, from: target + offset, relativeTo: nil)

        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        do {
            let renderer = try RealityRenderer()
            renderer.entities.append(root)
            renderer.entities.append(camera)
            renderer.activeCamera = camera
            let background = UIColor.systemBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
            renderer.cameraSettings.colorBackground = .color(background.cgColor)
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
            // A first pass lets the materials and textures settle; the second is the still.
            for _ in 0..<2 {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    do {
                        try renderer.updateAndRender(deltaTime: 1.0 / 30, cameraOutput: output,
                                                     onComplete: { _ in done.resume() })
                    } catch {
                        done.resume()
                    }
                }
            }
            renderer.entities.removeAll()
        } catch {
            log.error("still: renderer failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let image = image(from: texture, width: width, height: height)
        log.notice("still: \(buildingCode, privacy: .public) drawn in \(started.duration(to: .now), privacy: .public)")
        return image
    }

    /// The texture's pixels as an image.
    private static func image(from texture: any MTLTexture, width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: bytesPerRow, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                             | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
#endif

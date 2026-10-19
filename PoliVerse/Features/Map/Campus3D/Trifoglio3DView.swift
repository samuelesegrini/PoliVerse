#if DEBUG
import OSLog
import RealityKit
import SwiftUI

// PROTOTYPE — debug builds only, reached from the preview at the bottom and nowhere in the app.
//
// The walk from the campus to a classroom in 3D, on the Trifoglio (Edificio 13), Edificio 11
// and Edifici 1, 2, 3, 4 and 6: campus → building → floor → room, each step an animated
// camera move plus fades.
// The models come from `prototypes/trifoglio-3d-PROTOTYPE/esporta3d.py`, which extrudes
// the same outlines and CAD floor plans the map illustrations are drawn from. Their
// entities carry the Politecnico codes as names, so a room is found by its `csiv` —
// the same code as ``Classroom/roomCode``.
//
// Loading works like a map's tiles: the campus alone comes before the first frame, and a
// building's floors are read only when the camera heads for it, during the flight there,
// with the few visited last kept and the rest let go. The numbers this is tuned against,
// and the bench that measures them, are in `prototypes/trifoglio-3d-PROTOTYPE/banco/`.

/// Where the camera stands on the walk from the campus to a classroom.
enum Trifoglio3DLevel: Equatable {
    /// The whole campus from above.
    case campus
    /// One building, by its `csie`, with the other buildings faded.
    case building(String)
    /// One floor, by its `csip`: the shell gone, the floors above lifted away.
    case floor(String)
    /// One classroom, by its floor's `csip` and its own `csiv`.
    case room(floor: String, room: String)
    /// Inside a classroom, standing behind the last row and looking at the lectern.
    case inside(floor: String, room: String)
}

/// A building's floors and classrooms, as the exporter writes them next to the models.
struct Trifoglio3DPlan: Decodable {
    /// One floor of the building.
    struct Floor: Decodable, Identifiable {
        /// The floor's code, which also names its entity.
        let csip: String
        /// Height of its floor slab, in metres above the ground floor.
        let quota: Float
        /// The classrooms on it.
        let aule: [Room]
        /// The floor's code.
        var id: String { csip }
    }

    /// One classroom.
    struct Room: Decodable, Identifiable {
        /// The room's space code, which also names its entity.
        let csiv: String
        /// The code on the door, for example `"T.1.2"`.
        let sigla: String
        /// How many seats it has, where recorded.
        let posti: Int?
        /// Where to stand inside it, for tiered classrooms.
        let interno: Interior?
        /// The room's code.
        var id: String { csiv }
    }

    /// The view from inside a classroom, in the scene's metres.
    struct Interior: Decodable {
        /// The eye, standing behind the last row: x, height, z.
        let occhio: [Float]
        /// The point it looks at, over the lectern: x, height, z.
        let guarda: [Float]
        /// The entity holding the walls, ceiling and lights, when it is not named after the
        /// room: the Aula Magna's two rooms share one.
        let nodo: String?
        /// ``occhio`` as a point.
        var eye: SIMD3<Float> { SIMD3(occhio[0], occhio[1], occhio[2]) }
        /// ``guarda`` as a point.
        var look: SIMD3<Float> { SIMD3(guarda[0], guarda[1], guarda[2]) }
    }

    /// The building's code, `csie`.
    let csie: String
    /// The building's name.
    let nome: String?
    /// The building's number on the campus.
    let numero: String?
    /// The floors, lowest first.
    let piani: [Floor]
}

/// The scene: entities, camera and the animations between levels.
@Observable
final class Trifoglio3DScene {
    /// Where the camera is now.
    private(set) var level: Trifoglio3DLevel = .campus
    /// Every building's floors and classrooms, by `csie`, once loaded.
    private(set) var plans: [String: Trifoglio3DPlan] = [:]
    /// The floors and classrooms of the building the camera is on.
    var plan: Trifoglio3DPlan? { plans[csie] }
    /// Why the scene could not load, if it could not.
    private(set) var failure: String?
    /// Where the lit classroom's label sits on screen, or `nil` when there is none in view.
    private(set) var labelPoint: CGPoint?
    /// The size of the view the scene is drawn in, for placing the label.
    var viewSize: CGSize = .zero
    /// When on, every animation jumps to its end.
    var reduceMotion = false

    /// The buildings that have floors to walk into, in the order the campus offers them.
    static let buildings = ["MIA0203", "MIA0201", "MIA0101", "MIA0102", "MIA0103", "MIA0104", "MIA0106", "MIA0314", "MIA0403", "MIA1401", "MIA0306", "MIA0301", "MIA0302", "MIA0402", "MIA0601", "MIA0603", "MIA0901", "MIA0202", "MIA0206", "MIA0207", "MIA0208", "MIA0209", "MIA0214", "MIA0113", "MIA0109", "MIA0110", "MIA0114", "MIA0115", "MIA0105", "MIA0107", "MIA0108", "MIA0111", "MIA0112", "MIA0205", "MIA0212", "MIA0215"]
    /// The building the camera is on, or was on last.
    private(set) var csie = "MIA0203"
    /// Everything the scene adds to the view hangs from here.
    @ObservationIgnored private let root = Entity()
    /// The camera every move animates.
    @ObservationIgnored private let camera = Entity()
    /// The sun, the one light that casts shadows.
    @ObservationIgnored private let sun = Entity()
    /// The campus: terrain, trees and every building's outer shell.
    @ObservationIgnored private var campus: Entity?
    /// The Giuriati sports centre and its block east of the campus: ground, pitches, track,
    /// trees and building footprints, in the campus frame. Optional.
    @ObservationIgnored private var giuriati: Entity?
    /// Each building's simplified shell from `campus_lontano.usdz`, by `csie`, hung inside
    /// its detailed shell: drawn from the campus view instead of it, with 60 % fewer
    /// triangles. Empty when the bundle has no such file.
    @ObservationIgnored private var distant: [String: Entity] = [:]
    /// The floors of the buildings loaded so far, each with its slab, cut walls and rooms,
    /// by `csie`. At most ``keptBuildings`` of them.
    @ObservationIgnored private(set) var models: [String: Entity] = [:]
    /// Loads under way, by `csie`, so a building asked for twice is read once.
    @ObservationIgnored private var loading: [String: Task<Entity?, Never>] = [:]
    /// The loaded buildings, the one used last at the end.
    @ObservationIgnored private var recent: [String] = []
    /// The floors whose rooms already have their tap shapes, by entity.
    @ObservationIgnored private var tappableFloors: Set<Entity.ID> = []
    /// How many buildings' floors stay in memory. Each is 1–8 MB on the GPU; going back to
    /// one just visited is instant, and the campus never holds all 36.
    static let keptBuildings = 4
    /// The floors of the building the camera is on.
    private var building: Entity? { models[csie] }
    /// Keeps the per-frame callback alive.
    @ObservationIgnored private var subscription: EventSubscription?

    /// When ``load(into:)`` started, the campus was in the scene, and the first frame with
    /// it was drawn, with the app's memory then: what ``Trifoglio3DBench`` reports.
    @ObservationIgnored private(set) var loadStarted: ContinuousClock.Instant?
    @ObservationIgnored private(set) var campusLoaded: ContinuousClock.Instant?
    @ObservationIgnored private(set) var firstFrame: ContinuousClock.Instant?
    @ObservationIgnored private(set) var memoryAtFirstFrame: UInt64?
    /// Called once a frame with the time since the last one, while the bench listens.
    @ObservationIgnored var onFrame: ((TimeInterval) -> Void)?

    /// The orbit the camera sits on: what it looks at, from how far, how far from vertical
    /// and from which side. Animating these rather than positions makes every move an arc.
    @ObservationIgnored private var target: SIMD3<Float> = [30, 0, 150]
    @ObservationIgnored private var distance: Float = 520
    @ObservationIgnored private var polar: Float = 0.95
    @ObservationIgnored private var azimuth: Float = Trifoglio3DScene.southWest
    /// The side every flight looks from: the south-west, as the isometric drawings.
    private static let southWest: Float = -.pi / 4
    /// The camera's vertical field of view, in degrees.
    private let fieldOfView: Float = 35

    /// The animations running, stepped once a frame.
    @ObservationIgnored private var tweens: [Tween] = []
    /// Seconds since the scene started, advanced once a frame.
    @ObservationIgnored private var clock: Double = 0
    /// The lit classroom, the glowing copy laid over it, when it was lit, and the point its
    /// label hangs from.
    @ObservationIgnored private var lit: (room: Entity, glow: ModelEntity, since: Double, top: SIMD3<Float>)?
    /// The name of the glowing copies, so every one can be found and removed.
    private static let glowName = "Trifoglio3D_Luce"
    /// The end of the name of a classroom's interior: `<csiv>_Interno`.
    private static let interiorSuffix = "_Interno"
    /// What a building's simplified shell is called, after its `csie`.
    private static let distantSuffix = "_Lontano"
    /// Whether a move is under way. Taps and buttons wait for it to end rather than
    /// start a second move that fights the first over the camera and the fades.
    @ObservationIgnored private var isMoving = false

    /// One running animation.
    private struct Tween {
        /// ``clock`` when it started.
        let start: Double
        /// How long it runs, in seconds.
        let duration: Double
        /// Applies its progress, eased, from 0 to 1.
        let step: (Float) -> Void
        /// Resumed when it ends, if something waits for it.
        let done: CheckedContinuation<Void, Never>?
    }

    // MARK: - Loading

    /// Adds the camera, a sun and the campus to the view; everything else follows after
    /// the first frame.
    ///
    /// RealityView draws nothing until this returns, so it reads only `campus.usdz` and the
    /// small plan files the buttons need. The Giuriati block and the taps on the buildings
    /// come right after, and each building's floors when the camera heads for it.
    ///
    /// - Parameter content: The view's content.
    func load(into content: inout RealityViewCameraContent) async {
        loadStarted = .now
        content.camera = .virtual
        var lens = PerspectiveCameraComponent()
        lens.near = 1
        lens.far = 4000
        lens.fieldOfViewInDegrees = fieldOfView
        camera.components.set(lens)
        root.addChild(camera)

        sun.components.set(DirectionalLightComponent(color: .white, intensity: 2600))
        sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 700, depthBias: 2))
        sun.look(at: [20, 0, 140], from: [-160, 260, 220], relativeTo: nil)
        root.addChild(sun)
        // A weaker light from the other side, so walls in shade are grey rather than black.
        let fill = Entity()
        fill.components.set(DirectionalLightComponent(color: .white, intensity: 900))
        fill.look(at: [20, 0, 140], from: [220, 180, -120], relativeTo: nil)
        root.addChild(fill)
        content.add(root)

        await loadCampus()
        campusLoaded = .now
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let delta = event.deltaTime
            MainActor.assumeIsolated { self?.step(delta) }
        }
        aim()
        Task { await loadAfterFirstFrame() }
    }

    /// Reads the campus and every building's plan file, and adds the campus to the scene.
    func loadCampus() async {
        let signpost = Trifoglio3DSignpost.begin(.campus)
        defer { Trifoglio3DSignpost.end(signpost) }
        guard let campusURL = Bundle.main.url(forResource: "campus", withExtension: "usdz")
        else { failure = "Modelli non trovati nel bundle (Preview Content/Trifoglio3D)."; return }
        do {
            let campus = try await Entity(contentsOf: campusURL)
            root.addChild(campus)
            self.campus = campus
        } catch {
            failure = "Campus non caricato: \(error.localizedDescription)"
            return
        }
        for csie in Self.buildings {
            guard let planURL = Bundle.main.url(forResource: csie, withExtension: "json"),
                  let data = try? Data(contentsOf: planURL),
                  let plan = try? JSONDecoder().decode(Trifoglio3DPlan.self, from: data)
            else { failure = "Piante di \(csie) non trovate nel bundle."; continue }
            plans[csie] = plan
        }
    }

    /// What the first frame can do without: the Giuriati block, the simplified shells and
    /// the taps on the buildings.
    func loadAfterFirstFrame() async {
        let signpost = Trifoglio3DSignpost.begin(.afterFirstFrame)
        defer { Trifoglio3DSignpost.end(signpost) }
        if let giuriatiURL = Bundle.main.url(forResource: "giuriati", withExtension: "usdz"),
           let giuriati = try? await Entity(contentsOf: giuriatiURL) {
            root.addChild(giuriati)
            self.giuriati = giuriati
        }
        await loadDistant()
        tappable(campus?.findEntity(named: "Edifici"))
    }

    /// Hangs each simplified shell of `campus_lontano.usdz` inside the building's detailed
    /// one, so fading, framing and taps keep working on the building's group, and shows
    /// them if the camera is on the campus.
    ///
    /// The file comes from `banco/lontano.py`, which `esporta3d.py` runs on `campus.usdz`.
    private func loadDistant() async {
        guard let url = Bundle.main.url(forResource: "campus_lontano", withExtension: "usdz"),
              let file = try? await Entity(contentsOf: url),
              let groups = file.findEntity(named: "Edifici")
        else { return }
        for group in Array(groups.children) {
            guard let detailed = exteriors.first(where: { $0.name == group.name }) else { continue }
            group.name += Self.distantSuffix
            detailed.addChild(group, preservingWorldTransform: true)
            distant[detailed.name] = group
        }
        setDistant(level == .campus)
    }

    /// Draws every building with its simplified shell, or with its detailed one.
    func setDistant(_ on: Bool) {
        for shell in exteriors {
            guard let far = distant[shell.name] else { continue }
            for part in shell.children { part.isEnabled = (part === far) == on }
        }
    }

    /// A building's floors, read from the bundle the first time and kept for the next.
    ///
    /// Asking again while the first read is under way waits for that one. Loading a fifth
    /// building lets go of the one used longest ago, never the one the camera is on.
    ///
    /// - Parameter csie: The building's code.
    /// - Returns: Its floors, hidden and see-through, or `nil` when it has no model.
    @discardableResult
    func loadBuilding(_ csie: String) async -> Entity? {
        if let model = models[csie] {
            recent.removeAll { $0 == csie }
            recent.append(csie)
            return model
        }
        if let task = loading[csie] { return await task.value }
        let task = Task { await readBuilding(csie) }
        loading[csie] = task
        let building = await task.value
        loading[csie] = nil
        guard let building else {
            failure = "Modelli di \(csie) non trovati nel bundle."
            return nil
        }
        root.addChild(building)
        models[csie] = building
        recent.append(csie)
        while recent.count > Self.keptBuildings, let oldest = recent.first(where: { $0 != self.csie }) {
            recent.removeAll { $0 == oldest }
            models.removeValue(forKey: oldest)?.removeFromParent()
        }
        return building
    }

    /// Lets taps reach every mesh under an entity.
    ///
    /// - Parameter entity: The entity whose meshes become tappable; nothing when `nil`.
    private func tappable(_ entity: Entity?) {
        guard let entity else { return }
        entity.generateCollisionShapes(recursive: true)
        visit(entity) { $0.components.set(InputTargetComponent()) }
    }

    /// Lets taps reach every mesh under an entity by its exact shape, so a tap on an
    /// L-shaped classroom, or on its tiers, never lands on the room next to it.
    ///
    /// - Parameter entity: The entity whose meshes become tappable; nothing when `nil`.
    private func tappableExactly(_ entity: Entity?) async {
        guard let entity else { return }
        var meshes: [(Entity, MeshResource)] = []
        visit(entity) { if let model = $0.components[ModelComponent.self] { meshes.append(($0, model.mesh)) } }
        for (part, mesh) in meshes {
            if let shape = try? await ShapeResource.generateStaticMesh(from: mesh) {
                part.components.set(CollisionComponent(shapes: [shape]))
            } else {
                part.generateCollisionShapes(recursive: false)
            }
            part.components.set(InputTargetComponent())
        }
    }

    /// Reads a building's floors from the bundle and readies them, without adding them to
    /// the scene: the interiors hidden, the whole see-through and disabled.
    ///
    /// The rooms' tap shapes wait for ``tappableRooms(on:)``: built for every floor they took
    /// most of the second a building needed on an iPhone 12 Pro, and only the floor on screen
    /// takes taps.
    func readBuilding(_ csie: String) async -> Entity? {
        let signpost = Trifoglio3DSignpost.begin(.building)
        defer { Trifoglio3DSignpost.end(signpost) }
        guard let url = Bundle.main.url(forResource: csie, withExtension: "usdz"),
              let building = try? await Entity(contentsOf: url)
        else { return nil }
        // Each tiered classroom's full walls, ceiling and lights stay hidden until the
        // camera goes inside: from above they would cover the room.
        visit(building) { if $0.name.hasSuffix(Self.interiorSuffix) { $0.isEnabled = false } }
        building.components.set(OpacityComponent(opacity: 0))
        building.isEnabled = false
        return building
    }

    /// Gives a floor's rooms their exact tap shapes, once: the floor's own, when the camera
    /// comes to it.
    ///
    /// - Parameter floor: The floor's entity, named by its `csip`.
    func tappableRooms(on floor: Entity) async {
        guard let rooms = floor.findEntity(named: floor.name + "_Locali"),
              tappableFloors.insert(rooms.id).inserted else { return }
        await tappableExactly(rooms)
    }

    // MARK: - Switches for the bench

    /// Turns the sun's shadows on or off, at once.
    func setShadows(_ on: Bool) {
        if on {
            sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 700, depthBias: 2))
        } else {
            sun.components.remove(DirectionalLightComponent.Shadow.self)
        }
    }

    /// Shows or hides, at once, the campus and Giuriati entities with these names.
    func setVisible(_ names: [String], _ visible: Bool) {
        for name in names {
            campus?.findEntity(named: name)?.isEnabled = visible
            giuriati?.findEntity(named: name)?.isEnabled = visible
        }
    }

    /// Shows or hides the whole campus and Giuriati: with both hidden, what is left of a frame
    /// is RealityKit's own cost.
    func setScene(_ visible: Bool) {
        campus?.isEnabled = visible
        giuriati?.isEnabled = visible
    }

    /// Makes every building's outer shell fully opaque at once, as on the campus.
    func setExteriorsOpaque() {
        exteriors.forEach { $0.components.set(OpacityComponent(opacity: 1)); $0.isEnabled = true }
    }

    /// Lets go of every loaded building but the one the camera is on, so the next
    /// ``loadBuilding(_:)`` of each reads from the bundle again.
    func unloadBuildings() {
        for csie in models.keys where csie != self.csie || level == .campus {
            models.removeValue(forKey: csie)?.removeFromParent()
            recent.removeAll { $0 == csie }
        }
    }

    // MARK: - The walk

    /// Walks to classroom T.1.2 on the ground floor from wherever the camera is: through
    /// the building and the floor from the campus, straight across from another room on
    /// the same floor, and nowhere at all when T.1.2 is already on screen.
    func tour() async {
        await go(to: .room(floor: "MIA0203000", room: "MIA0203000030"))
    }

    /// Animates to a level and waits until the move has finished. Does nothing when the
    /// camera is already there, or while another move is under way.
    ///
    /// - Parameter next: Where to go.
    func go(to next: Trifoglio3DLevel) async {
        guard !isMoving, next != level else { return }
        isMoving = true
        defer { isMoving = false }
        await move(to: next)
    }

    /// The steps of ``go(to:)``, which call each other to pass through the levels between.
    private func move(to next: Trifoglio3DLevel) async {
        guard campus != nil else { return }
        if case .inside(_, let csiv) = level { leave(csiv) }
        // Another building: through its outside first, the floors of the last one put away.
        if let other = Self.buildingCode(of: next), other != csie || level == .campus {
            if case .building = next {} else { await move(to: .building(other)) }
        }
        switch next {
        case .campus:
            unlight()
            level = next
            setDistant(true)
            exteriors.forEach { fade($0, to: 1) }
            models.values.forEach { fade($0, to: 0) }
            trees.forEach { fade($0, to: 1) }
            frame(campus?.findEntity(named: "Edifici"), polar: 0.95, margin: 0.9)

        case .building(let csie):
            unlight()
            level = next
            self.csie = csie
            setDistant(false)
            // As in Maps, the other buildings stay solid and only those standing between the
            // camera and this one go: see-through shells cost 37 fps against 57 on an iPhone 12 Pro.
            let blocking = blockers(of: shell, polar: 1.0, margin: 1.15)
            exteriors.forEach { fade($0, to: blocking.contains($0.name) ? 0 : 1) }
            models.values.forEach { fade($0, to: 0) }
            trees.forEach { fade($0, to: 1) }
            if let building = self.building { floors(of: building).forEach { lift($0, to: 0) } }
            frame(shell, polar: 1.0, margin: 1.15)
            // Its floors are read during the flight, ready for the tap on a floor.
            if models[csie] == nil { Task { await loadBuilding(csie) } }

        case .floor(let csip):
            guard let building = await loadBuilding(csie) else { return }
            unlight()
            level = next
            let order = floors(of: building).map(\.name)
            let chosen = order.firstIndex(of: csip) ?? 0
            fade(shell, to: 0, duration: 0.6)
            trees.forEach { fade($0, to: 0) }
            fade(building, to: 1)
            for (index, floor) in floors(of: building).enumerated() {
                if index > chosen {
                    // The floors above lift away and vanish…
                    lift(floor, to: Float(30 + (index - chosen) * 6))
                    fade(floor, to: 0, duration: 0.6)
                } else {
                    // …the ones below stay as ghosts under the chosen one.
                    lift(floor, to: 0)
                    fade(floor, to: index == chosen ? 1 : 0.12, duration: 0.8)
                }
            }
            frame(floors(of: building)[safe: chosen], polar: 0.6, margin: 1.0)
            // Its rooms take taps from now on; the shapes are built during the flight.
            if let floor = floors(of: building)[safe: chosen] { await tappableRooms(on: floor) }

        case .room(let csip, let csiv):
            if level != .floor(csip), !isRoom(on: csip) { await move(to: .floor(csip)) }
            guard let room = building?.findEntity(named: csiv) else { return }
            unlight()
            level = next
            light(room)
            // Wider than the room, so the corridors that lead to it stay in view.
            frame(room, polar: 0.5, margin: 2.4, duration: 1.1)

        case .inside(let csip, let csiv):
            guard let view = interior(csiv) else { return }
            if level != .room(floor: csip, room: csiv) { await move(to: .room(floor: csip, room: csiv)) }
            unlight()
            level = next
            setLens(near: 0.1, fieldOfView: 60)
            fade(interiorEntity(csiv), to: 1, duration: 0.9)
            let offset = view.eye - view.look
            let distance = length(offset)
            fly(to: view.look, distance: distance, polar: acos(offset.y / distance),
                azimuth: atan2(offset.x, offset.z), duration: 1.6)
        }
        await settle()
    }

    /// The building a level is in, by the first seven characters of its codes: `MIA0203`.
    private static func buildingCode(of level: Trifoglio3DLevel) -> String? {
        switch level {
        case .campus: nil
        case .building(let csie): csie
        case .floor(let csip), .room(let csip, _), .inside(let csip, _): String(csip.prefix(7))
        }
    }

    /// Whether the camera is already on, or in, a room of this floor.
    private func isRoom(on csip: String) -> Bool {
        switch level {
        case .room(let floor, _), .inside(let floor, _): floor == csip
        default: false
        }
    }

    /// Where to stand inside a classroom, when it has an interior.
    func interior(_ csiv: String) -> Trifoglio3DPlan.Interior? {
        plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.interno
    }

    /// Hides a classroom's interior again as the camera leaves it.
    private func leave(_ csiv: String) {
        fade(interiorEntity(csiv), to: 0, duration: 0.5)
        setLens(near: 1, fieldOfView: fieldOfView)
    }

    /// A classroom's walls, ceiling and lights.
    private func interiorEntity(_ csiv: String) -> Entity? {
        building?.findEntity(named: interior(csiv)?.nodo ?? csiv + Self.interiorSuffix)
    }

    /// Sets how near the camera still draws and how wide it sees: inside a room a tenth of
    /// a metre, where the desks are close, and a wide view, as a person standing in it;
    /// outside a metre, which keeps far surfaces from flickering, and the narrow view the
    /// framing is computed for.
    private func setLens(near: Float, fieldOfView degrees: Float) {
        guard var lens = camera.components[PerspectiveCameraComponent.self] else { return }
        lens.near = near
        lens.fieldOfViewInDegrees = degrees
        camera.components.set(lens)
    }

    /// Goes where a tap on the model points: a building on the campus, a room on a floor.
    ///
    /// - Parameter entity: The entity the tap landed on.
    func tapped(_ entity: Entity) async {
        switch level {
        case .campus, .building:
            // Climb to the building's group under "Edifici".
            var node: Entity? = entity
            while let current = node, current.parent?.name != "Edifici" { node = current.parent }
            if let name = node?.name, Self.buildings.contains(name) { await go(to: .building(name)) }
        case .floor(let csip), .room(let csip, _):
            let rooms = plan?.piani.first { $0.csip == csip }?.aule ?? []
            if rooms.contains(where: { $0.csiv == entity.name }) {
                await go(to: .room(floor: csip, room: entity.name))
            }
        case .inside:
            break      // inside, a tap lands on the tiers under the camera
        }
    }

    // MARK: - Orbit by hand

    /// Turns the orbit by a drag, for looking around while debugging.
    ///
    /// - Parameter translation: The drag's movement since the last call, in points.
    func orbit(by translation: CGSize) {
        azimuth -= Float(translation.width) * 0.006
        polar = min(max(polar - Float(translation.height) * 0.004, 0.1), 1.45)
        aim()
    }

    /// Moves the camera nearer or further by a pinch.
    ///
    /// - Parameter scale: The pinch's change since the last call; above 1 comes nearer.
    func zoom(by scale: CGFloat) {
        distance = min(max(distance / Float(scale), 12), 900)
        aim()
    }

    // MARK: - Pieces of the scene

    /// Every building's outer shell on the campus.
    private var exteriors: [Entity] { campus?.findEntity(named: "Edifici").map { Array($0.children) } ?? [] }
    /// The outer shell, on the campus, of the building the camera is on.
    private var shell: Entity? { exteriors.first { $0.name == csie } }
    /// The campus trees, crowns and trunks, which would stand in the way inside a floor.
    private var trees: [Entity] {
        ["Chiome", "Tronchi"].compactMap { campus?.findEntity(named: $0) }
            + ["Alberi_Chiome", "Alberi_Tronchi", "Filari_Chiome", "Filari_Tronchi"]
                .compactMap { giuriati?.findEntity(named: $0) }
    }

    /// A building's floors, lowest first.
    private func floors(of building: Entity) -> [Entity] {
        building.findEntity(named: "Piani").map { Array($0.children) } ?? []
    }

    // MARK: - Animations

    /// Fades an entity, its children with it; one faded to nothing is disabled so taps go
    /// through it.
    private func fade(_ entity: Entity?, to opacity: Float, duration: Double = 0.7) {
        guard let entity else { return }
        let from = entity.isEnabled ? entity.components[OpacityComponent.self]?.opacity ?? 1 : 0
        entity.isEnabled = true
        animate(duration) { k in
            entity.components.set(OpacityComponent(opacity: from + (opacity - from) * k))
            if k == 1, opacity == 0 { entity.isEnabled = false }
        }
    }

    /// Moves a floor up or down from where the exporter placed it.
    private func lift(_ floor: Entity, to height: Float, duration: Double = 0.8) {
        let from = floor.position.y
        animate(duration) { k in floor.position.y = from + (height - from) * k }
    }

    /// Flies the camera so an entity fills the view, whatever the view's shape.
    ///
    /// The entity's bounds are taken as a sphere and fitted inside the narrower of the
    /// two fields of view, so a phone held upright frames it as fully as a wide window.
    ///
    /// - Parameters:
    ///   - entity: What to frame; nothing happens when `nil`.
    ///   - polar: The camera's angle from vertical, in radians.
    ///   - margin: How much bigger than the entity the frame is; 1 is a tight fit.
    ///   - duration: How long the flight takes, in seconds.
    private func frame(_ entity: Entity?, polar: Float, margin: Float, duration: Double = 1.3) {
        guard let framed = framing(entity, margin: margin) else { return }
        fly(to: framed.box.center, distance: framed.distance, polar: polar, duration: duration)
    }

    /// The bounds of what ``frame(_:polar:margin:duration:)`` frames and how far away the
    /// camera stands to fit it, or `nil` when there is nothing to frame.
    private func framing(_ entity: Entity?, margin: Float) -> (box: BoundingBox, distance: Float)? {
        guard let entity else { return nil }
        let box = entity.visualBounds(relativeTo: nil)
        guard !box.isEmpty else { return nil }
        let radius = max(length(box.extents) / 2, 4) * margin
        let vertical = fieldOfView * .pi / 180
        let aspect = viewSize.height > 0 ? Float(viewSize.width / viewSize.height) : 1
        let horizontal = 2 * atan(tan(vertical / 2) * aspect)
        return (box, radius / sin(min(vertical, horizontal) / 2))
    }

    /// The buildings whose shells stand between the camera, once framed on an entity from
    /// the south-west, and that entity: lines from the eye to its centre and to the middle
    /// of each side of its top pass through their bounds.
    private func blockers(of entity: Entity?, polar: Float, margin: Float) -> Set<String> {
        guard let entity, let framed = framing(entity, margin: margin) else { return [] }
        let (box, distance) = (framed.box, framed.distance)
        let a = Self.southWest
        let eye = box.center + SIMD3(sin(polar) * sin(a), cos(polar), sin(polar) * cos(a)) * distance
        let (lo, hi) = (box.min, box.max)
        let mid = box.center
        let targets: [SIMD3<Float>] = [mid, [mid.x, hi.y, mid.z], [lo.x, hi.y, mid.z], [hi.x, hi.y, mid.z],
                                       [mid.x, hi.y, lo.z], [mid.x, hi.y, hi.z]]
        var names: Set<String> = []
        for other in exteriors where other.name != entity.name {
            let bounds = other.visualBounds(relativeTo: nil)
            if targets.contains(where: { Self.segment(from: eye, to: $0, hits: bounds) }) { names.insert(other.name) }
        }
        return names
    }

    /// Whether the segment between two points passes through a box (the slab test).
    private static func segment(from p: SIMD3<Float>, to q: SIMD3<Float>, hits box: BoundingBox) -> Bool {
        guard !box.isEmpty else { return false }
        let d = q - p
        var (t0, t1): (Float, Float) = (0, 1)
        for axis in 0..<3 {
            if abs(d[axis]) < 1e-6 {
                if p[axis] < box.min[axis] || p[axis] > box.max[axis] { return false }
                continue
            }
            var (near, far) = ((box.min[axis] - p[axis]) / d[axis], (box.max[axis] - p[axis]) / d[axis])
            if near > far { swap(&near, &far) }
            t0 = max(t0, near)
            t1 = min(t1, far)
            if t0 > t1 { return false }
        }
        return true
    }

    /// Flies the camera along its orbit to look at a point from a distance and an angle,
    /// turning back to the south-west, or to another side, if the orbit was dragged elsewhere.
    private func fly(to point: SIMD3<Float>, distance: Float, polar: Float,
                     azimuth: Float = Trifoglio3DScene.southWest, duration: Double = 1.3) {
        let (t0, d0, p0) = (target, self.distance, self.polar)
        // The shortest way round.
        let a0 = self.azimuth
        let turn = remainder(azimuth - a0, 2 * .pi)
        animate(duration) { [self] k in
            target = t0 + (point - t0) * k
            // Further out in the middle, so the camera lifts and settles.
            self.distance = d0 + (distance - d0) * k + sin(.pi * k) * abs(distance - d0) * 0.15
            self.polar = p0 + (polar - p0) * k
            self.azimuth = a0 + turn * k
            aim()
        }
    }

    /// Starts an animation, eased in and out. With Reduce Motion it jumps to the end.
    private func animate(_ duration: Double, _ step: @escaping (Float) -> Void) {
        if reduceMotion || duration == 0 { step(1); return }
        tweens.append(Tween(start: clock, duration: duration, step: step, done: nil))
    }

    /// Waits until every animation started so far has ended.
    private func settle() async {
        let left = tweens.map { $0.start + $0.duration - clock }.max() ?? 0
        guard left > 0 else { return }
        await withCheckedContinuation { done in
            tweens.append(Tween(start: clock, duration: left, step: { _ in }, done: done))
        }
    }

    /// Advances every animation, the lit room's pulse and its label by one frame.
    private func step(_ delta: TimeInterval) {
        clock += delta
        if firstFrame == nil {
            firstFrame = .now
            memoryAtFirstFrame = Trifoglio3DProbe.memory()
        }
        onFrame?(delta)
        for index in tweens.indices.reversed() {
            let tween = tweens[index]
            let t = Float(min(1, (clock - tween.start) / tween.duration))
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            tween.step(t == 1 ? 1 : eased)
            if t == 1 {
                tweens.remove(at: index)
                tween.done?.resume()
            }
        }
        pulse()
    }

    /// Places the camera on its orbit.
    private func aim() {
        let offset = SIMD3<Float>(sin(polar) * sin(azimuth), cos(polar), sin(polar) * cos(azimuth)) * distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    // MARK: - The lit room

    /// Lights a classroom in the warm colour of the illustrations' lit floors.
    ///
    /// The room itself is never touched: a glowing copy of its mesh is laid just over it,
    /// and switching off only removes that copy. Swapping the room's own materials and
    /// putting them back left earlier rooms yellow.
    private func light(_ room: Entity) {
        unlight()
        var source: Entity?
        visit(room) { if source == nil, $0.components.has(ModelComponent.self) { source = $0 } }
        guard let source, let model = source.components[ModelComponent.self] else { return }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.91, green: 0.64, blue: 0.23, alpha: 1))
        material.emissiveColor = .init(color: .init(red: 0.91, green: 0.64, blue: 0.23, alpha: 1))
        material.emissiveIntensity = 0.5
        let glow = ModelEntity(mesh: model.mesh, materials: [material])
        glow.name = Self.glowName
        source.addChild(glow)
        // Just above the room's 5 cm slab, so the two never flicker into each other.
        glow.setPosition(source.position(relativeTo: nil) + [0, 0.06, 0], relativeTo: nil)
        var top = room.visualBounds(relativeTo: nil).center
        top.y += 1
        lit = (room, glow, clock, top)
    }

    /// Removes the glowing copy, so no classroom stays lit.
    ///
    /// Only ``light(_:)`` makes one and it clears the last first, so there is never more
    /// than the one ``lit`` holds: no need to search every building's entities for others.
    private func unlight() {
        lit?.glow.removeFromParent()
        lit = nil
        labelPoint = nil
    }

    /// Breathes the lit classroom's glow and keeps its label over it.
    private func pulse() {
        guard let lit, var model = lit.glow.components[ModelComponent.self],
              var material = model.materials.first as? PhysicallyBasedMaterial else { return }
        material.emissiveIntensity = 0.35 + 0.3 * Float(sin((clock - lit.since) * 4))
        model.materials = [material]
        lit.glow.components.set(model)
        // A new point redraws the SwiftUI overlay, so it changes only when the camera
        // moved the label by half a point or more: a still view costs no layout per frame.
        let point = project(lit.top)
        if let point, let old = labelPoint, abs(point.x - old.x) < 0.5, abs(point.y - old.y) < 0.5 { return }
        labelPoint = point
    }

    /// Where a point in the scene lands on screen, or `nil` when it is behind the camera.
    private func project(_ point: SIMD3<Float>) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let eye = camera.transformMatrix(relativeTo: nil).inverse * SIMD4<Float>(point, 1)
        guard eye.z < 0 else { return nil }
        let focal = 1 / tan(fieldOfView * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        let x = (eye.x / -eye.z) * focal / aspect
        let y = (eye.y / -eye.z) * focal
        return CGPoint(x: CGFloat((x + 1) / 2) * viewSize.width, y: CGFloat((1 - y) / 2) * viewSize.height)
    }

    /// Calls a closure on an entity and everything under it.
    private func visit(_ entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children { visit(child, body) }
    }
}

/// The walk on screen: the 3D scene, where you are, and what you can go to next.
struct Trifoglio3DView: View {
    /// The scene and its animations.
    @State private var scene = Trifoglio3DScene()
    /// The drag's translation at the last change, to turn the orbit by the difference.
    @State private var lastDrag: CGSize = .zero
    /// The pinch's scale at the last change, to zoom by the difference.
    @State private var lastPinch: CGFloat = 1
    /// Reduce Motion, which makes every move a jump.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The bench that measures the walk on this device.
    @State private var bench = Trifoglio3DBench()
    /// Whether the bench's results are on screen.
    @State private var showsBench = false

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                await scene.load(into: &content)
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                Task { await scene.tapped(value.entity) }
            })
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .onChanged { value in
                    scene.orbit(by: CGSize(width: value.translation.width - lastDrag.width,
                                           height: value.translation.height - lastDrag.height))
                    lastDrag = value.translation
                }
                .onEnded { _ in lastDrag = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    scene.zoom(by: value.magnification / lastPinch)
                    lastPinch = value.magnification
                }
                .onEnded { _ in lastPinch = 1 })
            .overlay(alignment: .topLeading) { label }
            .overlay(alignment: .top) {
                if let step = bench.step {
                    Label(step, systemImage: "gauge.with.dots.needle.67percent")
                        .font(.footnote.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect()
                        .padding(.top, 8)
                }
            }
            .onAppear {
                scene.viewSize = proxy.size
                scene.reduceMotion = reduceMotion
            }
            .onChange(of: proxy.size) { _, size in scene.viewSize = size }
        }
        .background(Color(red: 0.91, green: 0.93, blue: 0.95))
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top) { crumbs }
        .safeAreaInset(edge: .bottom) { panel }
        .sheet(isPresented: $showsBench) { Trifoglio3DBenchView(bench: bench) }
        .task {
            // `-Trifoglio3DBench` runs the bench as soon as the campus is drawn.
            guard CommandLine.arguments.contains("-Trifoglio3DBench") else { return }
            while scene.firstFrame == nil { try? await Task.sleep(for: .milliseconds(100)) }
            await runBench()
        }
    }

    /// Runs the bench with nothing over the walk, then shows what it measured.
    private func runBench() async {
        await bench.run(on: scene)
        showsBench = true
    }

    /// The lit classroom's name and seats, floating over it.
    @ViewBuilder
    private var label: some View {
        if let point = scene.labelPoint, case .room(let csip, let csiv) = scene.level,
           let room = scene.plan?.piani.first(where: { $0.csip == csip })?.aule.first(where: { $0.csiv == csiv }) {
            Text(room.posti.map { "\(room.sigla) · \($0) posti" } ?? room.sigla)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.tint, in: .capsule)
                .fixedSize()
                .position(x: point.x, y: point.y - 22)
                .allowsHitTesting(false)
        }
    }

    /// Where the camera is, each earlier step a button back to it.
    private var crumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                crumb("Campus", to: .campus)
                if scene.level != .campus {
                    crumb(buildingName(scene.csie), to: .building(scene.csie))
                }
                if let csip = currentFloor {
                    crumb(floorName(csip), to: .floor(csip))
                }
                if case let (csip, csiv)? = currentRoom {
                    crumb(roomName(csiv), to: .room(floor: csip, room: csiv))
                }
                if case .inside = scene.level {
                    crumb("Dentro", to: scene.level)
                }
                Button("Misura", systemImage: "gauge.with.dots.needle.67percent") {
                    if bench.report != nil, bench.step == nil { showsBench = true } else { Task { await runBench() } }
                }
                .buttonStyle(.glass)
                .disabled(bench.step != nil)
                .contextMenu {
                    Button("Misura di nuovo") { Task { await runBench() } }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
    }

    /// One step of the path.
    private func crumb(_ title: String, to level: Trifoglio3DLevel) -> some View {
        Button(title) { Task { await scene.go(to: level) } }
            .buttonStyle(.glass)
            .disabled(level == scene.level)
    }

    /// What can be chosen from here, and the button that walks the whole way.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = scene.failure {
                Text(failure).foregroundStyle(.red)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) { choices }
            }
            .scrollIndicators(.hidden)
            if case let (csip, csiv)? = currentRoom, scene.interior(csiv) != nil {
                // The Edificio 11's sunken patio is entered like a classroom.
                let place = scene.plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.sigla == "Patio" ? "nel patio" : "nell'aula"
                let leave = place == "nel patio" ? "dal patio" : "dall'aula"
                if case .inside = scene.level {
                    Button("Esci \(leave)") { Task { await scene.go(to: .room(floor: csip, room: csiv)) } }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Entra \(place)") { Task { await scene.go(to: .inside(floor: csip, room: csiv)) } }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button("Portami all'aula T.1.2") { Task { await scene.tour() } }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    /// The buildings, floors or rooms the current level offers.
    @ViewBuilder
    private var choices: some View {
        switch scene.level {
        case .campus:
            ForEach(Trifoglio3DScene.buildings, id: \.self) { csie in
                Button(buildingName(csie, full: true)) { Task { await scene.go(to: .building(csie)) } }
                    .buttonStyle(.glass)
            }
        case .building:
            ForEach((scene.plan?.piani ?? []).reversed()) { floor in
                Button(floorName(floor.csip)) { Task { await scene.go(to: .floor(floor.csip)) } }
                    .buttonStyle(.glass)
            }
        case .floor(let csip), .room(let csip, _), .inside(let csip, _):
            ForEach(scene.plan?.piani.first { $0.csip == csip }?.aule ?? []) { room in
                Button(room.sigla) { Task { await scene.go(to: .room(floor: csip, room: room.csiv)) } }
                    .buttonStyle(.glass)
                    .disabled(scene.level == .room(floor: csip, room: room.csiv))
            }
        }
    }

    /// The floor the camera is on, if it is on one.
    private var currentFloor: String? {
        switch scene.level {
        case .floor(let csip), .room(let csip, _), .inside(let csip, _): csip
        default: nil
        }
    }

    /// The classroom the camera is on or in, if any: its floor's code and its own.
    private var currentRoom: (String, String)? {
        switch scene.level {
        case .room(let csip, let csiv), .inside(let csip, let csiv): (csip, csiv)
        default: nil
        }
    }

    /// A building's name for a button: its number, and with `full` its name too.
    private func buildingName(_ csie: String, full: Bool = false) -> String {
        let plan = scene.plans[csie]
        let number = "Edificio \(plan?.numero ?? csie)"
        guard full, let name = plan?.nome else { return number }
        return "\(number) · \(name)"
    }

    /// A floor's name from the last characters of its code.
    private func floorName(_ csip: String) -> String {
        switch csip.suffix(3) {
        case "00S": "Seminterrato"
        case "000": "Piano terra"
        case "S00": "Soppalco"
        default: "Piano \(Int(csip.suffix(3)) ?? 0)"
        }
    }

    /// A classroom's door code from its space code.
    private func roomName(_ csiv: String) -> String {
        scene.plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.sigla ?? csiv
    }
}

/// The 3D walk's stretches of work, as Points of Interest intervals for Instruments and
/// for the bench in `PoliVerseTests/Trifoglio3DLoadTests.swift`.
///
/// Kept apart from ``PerfSignpost``: the walk is a debug prototype, and MetricKit keeps
/// only a few custom metrics per app.
nonisolated enum Trifoglio3DSignpost {
    /// The stretches of work that are timed.
    enum Name {
        /// ``Trifoglio3DScene/loadCampus()``: everything before the first frame.
        case campus
        /// ``Trifoglio3DScene/loadAfterFirstFrame()``: the Giuriati block and the taps.
        case afterFirstFrame
        /// One ``Trifoglio3DScene/loadBuilding(_:)`` that reads from the bundle.
        case building

        /// The name both Instruments and `XCTOSSignpostMetric` match on.
        var staticName: StaticString {
            switch self {
            case .campus: "trifoglio3d.campus"
            case .afterFirstFrame: "trifoglio3d.after-first-frame"
            case .building: "trifoglio3d.building"
            }
        }
    }

    /// One open interval.
    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
    }

    /// The Points of Interest signposter Instruments reads.
    private static let signposter = OSSignposter(subsystem: "segrini.samuele.PoliVerse", category: .pointsOfInterest)

    /// Opens an interval.
    static func begin(_ name: Name) -> Interval {
        Interval(name: name.staticName, state: signposter.beginInterval(name.staticName, id: signposter.makeSignpostID()))
    }

    /// Closes what ``begin(_:)`` opened.
    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
    }
}

private extension Array {
    /// The element at an index, or `nil` when the index is out of range.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview("Trifoglio 3D") {
    Trifoglio3DView()
}
#endif

#if DEBUG
import RealityKit
import SwiftUI

// PROTOTYPE — debug builds only, reached from the preview at the bottom and nowhere in the app.
//
// The walk from the campus to a classroom in 3D, on the Trifoglio (Edificio 13) alone:
// campus → building → floor → room, each step an animated camera move plus fades.
// The models come from `prototypes/trifoglio-3d-PROTOTYPE/esporta3d.py`, which extrudes
// the same outlines and CAD floor plans the map illustrations are drawn from. Their
// entities carry the Politecnico codes as names, so a room is found by its `csiv` —
// the same code as ``Classroom/roomCode``.

/// Where the camera stands on the walk from the campus to a classroom.
enum Trifoglio3DLevel: Equatable {
    /// The whole campus from above.
    case campus
    /// The Trifoglio, with the other buildings faded.
    case building
    /// One floor, by its `csip`: the shell gone, the floors above lifted away.
    case floor(String)
    /// One classroom, by its floor's `csip` and its own `csiv`.
    case room(floor: String, room: String)
}

/// The Trifoglio's floors and classrooms, as the exporter writes them next to the models.
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
        /// The room's code.
        var id: String { csiv }
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
    /// The floors and classrooms, once loaded.
    private(set) var plan: Trifoglio3DPlan?
    /// Why the scene could not load, if it could not.
    private(set) var failure: String?
    /// Where the lit classroom's label sits on screen, or `nil` when there is none in view.
    private(set) var labelPoint: CGPoint?
    /// The size of the view the scene is drawn in, for placing the label.
    var viewSize: CGSize = .zero
    /// When on, every animation jumps to its end.
    var reduceMotion = false

    /// The building every step of the walk goes to.
    let csie = "MIA0203"
    /// Everything the scene adds to the view hangs from here.
    @ObservationIgnored private let root = Entity()
    /// The camera every move animates.
    @ObservationIgnored private let camera = Entity()
    /// The campus: terrain, trees and every building's outer shell.
    @ObservationIgnored private var campus: Entity?
    /// The Trifoglio's floors, each with its slab, cut walls and rooms.
    @ObservationIgnored private var building: Entity?
    /// Keeps the per-frame callback alive.
    @ObservationIgnored private var subscription: EventSubscription?

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
    /// The lit classroom, its materials before it was lit, and when it was lit.
    @ObservationIgnored private var lit: (entity: Entity, materials: [any RealityKit.Material], since: Double)?

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

    /// Loads the models from the bundle and adds them, the camera and a sun to the view.
    ///
    /// - Parameter content: The view's content.
    func load(into content: inout RealityViewCameraContent) async {
        content.camera = .virtual
        var lens = PerspectiveCameraComponent()
        lens.near = 1
        lens.far = 4000
        lens.fieldOfViewInDegrees = fieldOfView
        camera.components.set(lens)
        root.addChild(camera)

        let sun = Entity()
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

        do {
            guard let campusURL = Bundle.main.url(forResource: "campus", withExtension: "usdz"),
                  let buildingURL = Bundle.main.url(forResource: csie, withExtension: "usdz"),
                  let planURL = Bundle.main.url(forResource: csie, withExtension: "json")
            else { failure = "Modelli non trovati nel bundle (Preview Content/Trifoglio3D)."; return }
            plan = try JSONDecoder().decode(Trifoglio3DPlan.self, from: Data(contentsOf: planURL))
            let campus = try await Entity(contentsOf: campusURL)
            let building = try await Entity(contentsOf: buildingURL)
            tappable(campus.findEntity(named: "Edifici"))
            for floor in floors(of: building) {
                tappable(floor.findEntity(named: floor.name + "_Locali"))
            }
            building.components.set(OpacityComponent(opacity: 0))
            building.isEnabled = false
            root.addChild(campus)
            root.addChild(building)
            self.campus = campus
            self.building = building
        } catch {
            failure = "Modelli non caricati: \(error.localizedDescription)"
        }

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let delta = event.deltaTime
            MainActor.assumeIsolated { self?.step(delta) }
        }
        aim()
    }

    /// Lets taps reach every mesh under an entity.
    ///
    /// - Parameter entity: The entity whose meshes become tappable; nothing when `nil`.
    private func tappable(_ entity: Entity?) {
        guard let entity else { return }
        entity.generateCollisionShapes(recursive: true)
        visit(entity) { $0.components.set(InputTargetComponent()) }
    }

    // MARK: - The walk

    /// Walks the whole way, from the campus to classroom T.1.2 on the ground floor.
    func tour() async {
        await go(to: .campus)
        await go(to: .building)
        await go(to: .floor("MIA0203000"))
        await go(to: .room(floor: "MIA0203000", room: "MIA0203000030"))
    }

    /// Animates to a level and waits until the move has finished.
    ///
    /// - Parameter next: Where to go.
    func go(to next: Trifoglio3DLevel) async {
        guard campus != nil, let building else { return }
        switch next {
        case .campus:
            unlight()
            level = next
            exteriors.forEach { fade($0, to: 1) }
            fade(building, to: 0)
            trees.forEach { fade($0, to: 1) }
            frame(campus?.findEntity(named: "Edifici"), polar: 0.95, margin: 0.9)

        case .building:
            unlight()
            level = next
            exteriors.forEach { fade($0, to: $0.name == csie ? 1 : 0.18) }
            fade(building, to: 0)
            trees.forEach { fade($0, to: 1) }
            floors(of: building).forEach { lift($0, to: 0) }
            frame(shell, polar: 1.0, margin: 1.15)

        case .floor(let csip):
            if level == .campus { await go(to: .building) }
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

        case .room(let csip, let csiv):
            if level != .floor(csip), !isRoom(on: csip) { await go(to: .floor(csip)) }
            unlight()
            level = next
            guard let room = building.findEntity(named: csiv) else { return }
            light(room)
            // Wider than the room, so the corridors that lead to it stay in view.
            frame(room, polar: 0.5, margin: 2.4, duration: 1.1)
        }
        await settle()
    }

    /// Whether the camera is already on a room of this floor.
    private func isRoom(on csip: String) -> Bool {
        if case .room(let floor, _) = level { return floor == csip }
        return false
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
            if node?.name == csie { await go(to: .building) }
        case .floor(let csip), .room(let csip, _):
            let rooms = plan?.piani.first { $0.csip == csip }?.aule ?? []
            if rooms.contains(where: { $0.csiv == entity.name }) {
                await go(to: .room(floor: csip, room: entity.name))
            }
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
    /// The Trifoglio's outer shell on the campus.
    private var shell: Entity? { exteriors.first { $0.name == csie } }
    /// The campus trees, crowns and trunks, which would stand in the way inside a floor.
    private var trees: [Entity] { ["Chiome", "Tronchi"].compactMap { campus?.findEntity(named: $0) } }

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
        guard let entity else { return }
        let box = entity.visualBounds(relativeTo: nil)
        guard !box.isEmpty else { return }
        let radius = max(length(box.extents) / 2, 4) * margin
        let vertical = fieldOfView * .pi / 180
        let aspect = viewSize.height > 0 ? Float(viewSize.width / viewSize.height) : 1
        let horizontal = 2 * atan(tan(vertical / 2) * aspect)
        let distance = radius / sin(min(vertical, horizontal) / 2)
        fly(to: box.center, distance: distance, polar: polar, duration: duration)
    }

    /// Flies the camera along its orbit to look at a point from a distance and an angle,
    /// turning back to the south-west if the orbit was dragged elsewhere.
    private func fly(to point: SIMD3<Float>, distance: Float, polar: Float, duration: Double = 1.3) {
        let (t0, d0, p0) = (target, self.distance, self.polar)
        // The shortest way round to the south-west.
        let a0 = azimuth
        let turn = remainder(Self.southWest - a0, 2 * .pi)
        animate(duration) { [self] k in
            target = t0 + (point - t0) * k
            // Further out in the middle, so the camera lifts and settles.
            self.distance = d0 + (distance - d0) * k + sin(.pi * k) * abs(distance - d0) * 0.15
            self.polar = p0 + (polar - p0) * k
            azimuth = a0 + turn * k
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
    private func light(_ room: Entity) {
        guard var model = room.components[ModelComponent.self] else { return }
        lit = (room, model.materials, clock)
        var glow = PhysicallyBasedMaterial()
        glow.baseColor = .init(tint: .init(red: 0.91, green: 0.64, blue: 0.23, alpha: 1))
        glow.emissiveColor = .init(color: .init(red: 0.91, green: 0.64, blue: 0.23, alpha: 1))
        glow.emissiveIntensity = 0.5
        model.materials = [glow]
        room.components.set(model)
    }

    /// Puts the lit classroom back as it was.
    private func unlight() {
        if let lit, var model = lit.entity.components[ModelComponent.self] {
            model.materials = lit.materials
            lit.entity.components.set(model)
        }
        lit = nil
        labelPoint = nil
    }

    /// Breathes the lit classroom's glow and keeps its label over it.
    private func pulse() {
        guard let lit, var model = lit.entity.components[ModelComponent.self],
              var glow = model.materials.first as? PhysicallyBasedMaterial else { return }
        glow.emissiveIntensity = 0.35 + 0.3 * Float(sin((clock - lit.since) * 4))
        model.materials = [glow]
        lit.entity.components.set(model)
        var top = lit.entity.visualBounds(relativeTo: nil).center
        top.y += 1
        labelPoint = project(top)
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
                    crumb("Edificio 13", to: .building)
                }
                if let csip = currentFloor {
                    crumb(floorName(csip), to: .floor(csip))
                }
                if case .room(_, let csiv) = scene.level {
                    crumb(roomName(csiv), to: scene.level)
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
            Button("Portami all'aula T.1.2") { Task { await scene.tour() } }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(16)
    }

    /// The buildings, floors or rooms the current level offers.
    @ViewBuilder
    private var choices: some View {
        switch scene.level {
        case .campus:
            Button("Edificio 13 · Trifoglio") { Task { await scene.go(to: .building) } }
                .buttonStyle(.glass)
        case .building:
            ForEach((scene.plan?.piani ?? []).reversed()) { floor in
                Button(floorName(floor.csip)) { Task { await scene.go(to: .floor(floor.csip)) } }
                    .buttonStyle(.glass)
            }
        case .floor(let csip), .room(let csip, _):
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
        case .floor(let csip), .room(let csip, _): csip
        default: nil
        }
    }

    /// A floor's name from the last characters of its code.
    private func floorName(_ csip: String) -> String {
        switch csip.suffix(3) {
        case "00S": "Seminterrato"
        case "000": "Piano terra"
        default: "Piano \(Int(csip.suffix(3)) ?? 0)"
        }
    }

    /// A classroom's door code from its space code.
    private func roomName(_ csiv: String) -> String {
        scene.plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.sigla ?? csiv
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

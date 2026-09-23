import CoreMotion
import SwiftUI

// The student's card at the top of the profile: the Politecnico's facade on
// the front with the logo, the name and the matricola heat-pressed into it in
// silver foil, and on the back the contact's QR code with the logo pressed
// blind into the card.
//
// It behaves as the object it draws. A tap turns it over, lifting it off the
// page on the way; a drag tilts it; and the foil and the sheen follow the
// phone's tilt, so the metal catches the light the way a real card's does.

/// The student's card, which turns over on a tap.
struct StudentCard: View {
    /// The student the card belongs to, or `nil` for a guest.
    let student: Student?
    /// "Laurea Magistrale · Ingegneria Informatica", under the name.
    var subtitle: String?
    /// Starts on the back, for previews.
    var startsFlipped = false
    /// Where the light comes from, for previews; `nil` follows the phone.
    var fixedLight: CGSize?

    /// The card's angle about its vertical axis: 0 shows the front, 180 the back.
    @State private var angle: Double = 0
    /// How far the card is being dragged, which tilts it.
    @State private var drag: CGSize = .zero
    /// The phone's tilt, which moves the light across the foil.
    @State private var motion = CardMotion()
    /// The contact's QR code for the back, drawn once when the page opens.
    @State private var qr: CGImage?
    /// Whether the interface should keep movement to a minimum.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the back is the side facing the student.
    private var showsBack: Bool { angle.remainder(dividingBy: 360).magnitude > 90 }

    /// Where the light falls, from -1 to 1 on each axis.
    private var light: CGSize {
        if let fixedLight { return fixedLight }
        if reduceMotion { return .zero }
        return CGSize(width: motion.tilt.width + drag.width / 300, height: motion.tilt.height + drag.height / 300)
    }

    /// The view's content.
    var body: some View {
        Button(action: flip) {
            FlippingCard(angle: angle, light: light) {
                StudentCardFront(student: student, subtitle: subtitle, light: light)
            } back: {
                StudentCardBack(student: student, qr: qr, light: light)
            }
            .rotation3DEffect(.degrees(Double(-drag.height) / 14), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(Double(drag.width) / 14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
        .buttonStyle(CardPressStyle())
        .simultaneousGesture(tiltGesture)
        .sensoryFeedback(.impact(weight: .medium), trigger: showsBack)
        .onAppear {
            if startsFlipped { angle = 180 }
            if fixedLight == nil, !reduceMotion { motion.start() }
        }
        .onDisappear { motion.stop() }
        // Drawn as soon as the page is up and off the main thread, so the
        // first turn has it ready rather than rendering it mid-animation.
        .task(id: student?.email) {
            guard let student else { qr = nil; return }
            let contact = ProfileContact(student: student)
            qr = await Task.detached(priority: .utility) { contact.qrCode(scale: 8) }.value
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Gira la tessera")
        .accessibilityAddTraits(.isButton)
    }

    /// Turns the card over, always the same way round, so it reads as one
    /// object spinning rather than a picture swapping.
    private func flip() {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.75, bounce: 0.28)
        withAnimation(animation) { angle += 180 }
    }

    /// A drag tilts the card towards the finger, and it springs back flat.
    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !reduceMotion else { return }
                drag = CGSize(width: value.translation.width.clamped(to: -140...140),
                              height: value.translation.height.clamped(to: -140...140))
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.6, bounce: 0.45)) { drag = .zero }
            }
    }

    /// What VoiceOver reads for the side facing up.
    private var accessibilityLabel: Text {
        guard let student else { return Text("Tessera, ospite") }
        if showsBack { return Text("Retro della tessera: codice QR del contatto di \(student.fullName)") }
        return Text("Tessera di \(student.fullName), matricola \(student.matricola)")
    }
}

// MARK: - Turning over

/// The two faces of the card on one plane, turned by `angle`.
///
/// Animatable, so SwiftUI interpolates the angle itself and the faces swap at
/// exactly the moment the card is edge-on; a crossfade would show both halves
/// ghosted at once. The card lifts towards the student on the way round and
/// settles back, and the sheen sweeps across it as it turns.
private struct FlippingCard<Front: View, Back: View>: View, Animatable {
    /// The card's angle, in degrees.
    var angle: Double
    /// Where the light falls, from -1 to 1 on each axis.
    let light: CGSize
    /// The front face.
    @ViewBuilder let front: Front
    /// The back face.
    @ViewBuilder let back: Back

    /// The value SwiftUI interpolates.
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    /// The view's content.
    var body: some View {
        let turned = angle.remainder(dividingBy: 360)
        let showsBack = turned.magnitude > 90
        // 0 flat, 1 edge-on: how far through the turn the card is.
        let lift = abs(sin(angle * .pi / 180))
        ZStack {
            if showsBack {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                front
            }
        }
        .aspectRatio(StudentCardMetrics.aspect, contentMode: .fit)
        .overlay { Sheen(offset: light.width * 0.6 + turned / 180) }
        .clipShape(.rect(cornerRadius: StudentCardMetrics.radius, style: .continuous))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .scaleEffect(1 + 0.06 * lift)
        .shadow(color: Color(red: 0.05, green: 0.14, blue: 0.34).opacity(0.3 - 0.12 * lift),
                radius: 22 + 14 * lift, y: 18 + 12 * lift)
    }
}

/// The card sinks a little under the finger, as a card pressed on a table does.
private struct CardPressStyle: ButtonStyle {
    /// The button's body.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// A band of light across the card, placed by the tilt.
private struct Sheen: View {
    /// Where the band sits, from -1 (left) to 1 (right).
    let offset: Double

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0.36),
                    .init(color: .white.opacity(0.22), location: 0.47),
                    .init(color: Color(red: 0.8, green: 0.87, blue: 1).opacity(0.14), location: 0.52),
                    .init(color: .white.opacity(0), location: 0.62),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: proxy.size.width * 2, height: proxy.size.height)
                .offset(x: proxy.size.width * (CGFloat(offset.clamped(to: -1.5...1.5)) * 0.5 - 0.5))
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Faces

/// Sizes shared by both faces, as fractions of the card's width.
private enum StudentCardMetrics {
    /// A bank card's proportions, ISO/IEC 7810 ID-1.
    static let aspect: CGFloat = 85.6 / 53.98
    /// The card's corner radius.
    static let radius: CGFloat = 24
    /// The Politecnico's blue at its deepest, under the white text.
    static let navy = Color(red: 0.055, green: 0.137, blue: 0.337)
}

/// The front: the facade, the logo and the name pressed into foil, the
/// student's name and course, and the matricola.
private struct StudentCardFront: View {
    /// The student, or `nil` for a guest.
    let student: Student?
    /// The course line under the name.
    let subtitle: String?
    /// Where the light falls.
    let light: CGSize

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let navy = StudentCardMetrics.navy
            ZStack {
                Image("PolitecnicoFacade")
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(
                    stops: [
                        // Deep behind the logo, so the silver reads against it.
                        .init(color: navy.opacity(0.9), location: 0),
                        .init(color: navy.opacity(0.55), location: 0.3),
                        .init(color: navy.opacity(0.3), location: 0.52),
                        .init(color: navy.opacity(0.94), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
                FoilFrame(light: light, width: width)

                VStack(alignment: .leading, spacing: 0) {
                    PolitecnicoMark(style: .foil(light), shape: .lockup, height: width * 0.13)
                    Spacer(minLength: 0)
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(student?.fullName ?? String(localized: "Ospite"))
                                .font(.system(size: width * 0.058, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.system(size: width * 0.036))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .opacity(0.88)
                            }
                        }
                        .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if let student {
                            Text(verbatim: student.matricola)
                                .font(.system(size: width * 0.038, weight: .bold))
                                .monospacedDigit()
                                .tracking(1)
                                .foilPressed(light)
                        }
                    }
                }
                .padding(width * 0.062)
            }
        }
    }
}

/// The back: the logo pressed blind into the card, the contact's QR code, and
/// the codes the student is asked for.
private struct StudentCardBack: View {
    /// The student, or `nil` for a guest.
    let student: Student?
    /// The contact's QR code, drawn by the card when the page opens.
    let qr: CGImage?
    /// Where the light falls.
    let light: CGSize

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(red: 0.15, green: 0.29, blue: 0.62),
                                        Color(red: 0.08, green: 0.19, blue: 0.44),
                                        Color(red: 0.04, green: 0.11, blue: 0.29)],
                               center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: width * 0.9)
                PolitecnicoMark(style: .blind, shape: .seal, height: height * 0.95)
                    .offset(x: -width * 0.12, y: height * 0.08)
                // Over the seal, so the frame runs across the impression.
                FoilFrame(light: light, width: width)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Spacer(minLength: 0)
                        if let student {
                            Text("Matricola")
                                .font(.system(size: width * 0.032, weight: .bold))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.75))
                            Text(verbatim: student.matricola)
                                .font(.system(size: width * 0.056, weight: .bold))
                                .monospacedDigit()
                                .foilPressed(light)
                            Text("Codice persona \(student.personCode)")
                                .font(.system(size: width * 0.032))
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Text("Accedi per avere la tua tessera")
                                .font(.system(size: width * 0.04, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        if let qr {
                            Image(decorative: qr, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(width * 0.022)
                                .frame(width: width * 0.36, height: width * 0.36)
                                .background(.white, in: .rect(cornerRadius: width * 0.045, style: .continuous))
                        }
                        Spacer(minLength: 0)
                        // The card looks like a badge, and a badge can be
                        // taken for an ID: it says plainly that it is not one.
                        Text("Non è un documento ufficiale")
                            .font(.system(size: width * 0.026))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(width * 0.062)
            }
        }
    }
}

/// A hairline of foil inset from the card's edge, the frame a pressed card has.
private struct FoilFrame: View {
    /// Where the light falls.
    let light: CGSize
    /// The card's width.
    let width: CGFloat

    /// The view's content.
    var body: some View {
        let inset = width * 0.025
        RoundedRectangle(cornerRadius: StudentCardMetrics.radius - inset, style: .continuous)
            .strokeBorder(Foil.gradient(light), lineWidth: 0.8)
            .opacity(0.55)
            .padding(inset)
            .accessibilityHidden(true)
    }
}

// MARK: - The logo

/// The Politecnico's logo, pressed into the card.
///
/// Drawn from the asset catalog's template images — `PolimiLogo`, the seal
/// with the name beside it, and `PolimiSeal`, the seal alone — so the foil
/// fills the mark itself. A build without them falls back to a placeholder
/// seal, with the name set in type beside it on the front.
private struct PolitecnicoMark: View {
    /// How the mark is pressed.
    enum Style {
        /// In silver foil, lit from `light`.
        case foil(CGSize)
        /// Pressed without foil: the card's own colour, raised by light and shadow.
        case blind
    }

    /// Which form of the logo.
    enum Shape {
        /// The seal with "Politecnico Milano 1863" beside it, for the front.
        case lockup
        /// The seal alone, for the back.
        case seal

        /// The asset's name.
        var asset: String {
            switch self {
            case .lockup: "PolimiLogo"
            case .seal: "PolimiSeal"
            }
        }
    }

    /// How the mark is pressed.
    let style: Style
    /// Which form of the logo.
    let shape: Shape
    /// The mark's height, in points; the width follows the logo's proportions.
    let height: CGFloat

    /// The view's content.
    var body: some View {
        Group {
            if UIImage(named: shape.asset) != nil {
                pressed(Image(shape.asset).renderingMode(.template).resizable().scaledToFit())
                    .frame(height: height)
            } else {
                HStack(spacing: height * 0.2) {
                    pressed(PlaceholderSeal().stroke(style: StrokeStyle(lineWidth: height * 0.04, lineCap: .round,
                                                                       lineJoin: .round)))
                        .frame(width: height, height: height)
                    if shape == .lockup {
                        pressed(Text(verbatim: "POLITECNICO\nMILANO 1863")
                            .font(.system(size: height * 0.26, weight: .bold))
                            .lineSpacing(1))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The mark in foil or blind, with the edges a press leaves.
    @ViewBuilder
    private func pressed(_ mark: some View) -> some View {
        switch style {
        case .foil(let light):
            mark.foilPressed(light)
        case .blind:
            mark.foregroundStyle(
                Color(red: 0.12, green: 0.25, blue: 0.55)
                    .shadow(.inner(color: .black.opacity(0.5), radius: 1.2, x: 0, y: 1.5))
                    .shadow(.drop(color: .white.opacity(0.14), radius: 0, x: 0, y: 1)))
                .opacity(0.9)
        }
    }
}

/// A seal standing in for the logo: two rings and a portico of columns.
nonisolated private struct PlaceholderSeal: Shape {
    /// The seal's outline in `rect`.
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(origin: p(2, 2), size: CGSize(width: 60 * s, height: 60 * s)))
        path.addEllipse(in: CGRect(origin: p(7, 7), size: CGSize(width: 50 * s, height: 50 * s)))
        path.move(to: p(18, 27)); path.addLine(to: p(32, 19)); path.addLine(to: p(46, 27))
        for x in [21, 27, 37, 43] as [CGFloat] {
            path.move(to: p(x, 29)); path.addLine(to: p(x, 42))
        }
        path.move(to: p(17, 45)); path.addLine(to: p(47, 45))
        return path
    }
}

// MARK: - Foil

/// Silver foil, lit from a direction.
private enum Foil {
    /// Bands of light and shade across the metal, slid by the tilt so the foil
    /// glints as the phone moves.
    static func gradient(_ light: CGSize) -> LinearGradient {
        let dx = light.width.clamped(to: -1...1) * 0.35
        let dy = light.height.clamped(to: -1...1) * 0.35
        return LinearGradient(
            stops: [
                .init(color: Color(white: 0.56), location: 0),
                .init(color: Color(white: 0.96), location: 0.18),
                .init(color: Color(white: 0.66), location: 0.34),
                .init(color: .white, location: 0.47),
                .init(color: Color(white: 0.6), location: 0.62),
                .init(color: Color(white: 0.92), location: 0.78),
                .init(color: Color(white: 0.5), location: 1),
            ],
            startPoint: UnitPoint(x: -dx, y: -dy),
            endPoint: UnitPoint(x: 1 - dx, y: 1 - dy))
    }
}

extension View {
    /// Fills the view's shape with foil pressed into the card, lit from `light`.
    ///
    /// The mark sits in a hollow the die left, so its edges answer the light
    /// the way a real press does: the wall nearest the light falls into shadow,
    /// the far wall catches it, and the card's rim around the hollow is lit on
    /// the far side. All three move as the phone tilts, and a narrow glint runs
    /// across the metal, so the impression reads as depth rather than print.
    ///
    /// - Parameter light: Where the light falls, from -1 to 1 on each axis.
    fileprivate func foilPressed(_ light: CGSize) -> some View {
        let lx = light.width.clamped(to: -1...1)
        let ly = light.height.clamped(to: -1...1)
        // Away from the light: the direction the press's shadows fall. Tilted
        // flat, the light is overhead and a little in front, as on a desk.
        let away = CGSize(width: -lx * 1.1, height: 0.8 - ly * 1.1)
        return foregroundStyle(
            Foil.gradient(light)
                .shadow(.inner(color: .black.opacity(0.5), radius: 0.7, x: away.width, y: away.height))
                .shadow(.drop(color: .black.opacity(0.5), radius: 0, x: -away.width * 0.6, y: -away.height * 0.6))
                .shadow(.drop(color: .white.opacity(0.32), radius: 0, x: away.width * 0.6, y: away.height * 0.6)))
            .overlay {
                FoilGlint(position: lx * 0.5 + ly * 0.25)
                    .mask { self }
            }
    }
}

/// The bright line a polished edge throws, placed by the tilt.
private struct FoilGlint: View {
    /// Where the line crosses the mark, from about -1 to 1.
    let position: CGFloat

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0.44),
                    .init(color: .white.opacity(0.85), location: 0.5),
                    .init(color: .white.opacity(0), location: 0.56),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: proxy.size.width * 2.4, height: proxy.size.height)
                .offset(x: proxy.size.width * (position - 0.7))
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Motion

/// The phone's tilt, from -1 to 1 on each axis, smoothed.
@MainActor @Observable
private final class CardMotion {
    /// Left–right and forward–back, each from -1 to 1.
    private(set) var tilt: CGSize = .zero

    /// The motion source, shared by every card on screen.
    private static let manager = CMMotionManager()

    /// Starts following the phone, sixty times a second, so the glint slides
    /// rather than steps.
    func start() {
        let manager = Self.manager
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude else { return }
            // A phone held to read sits about 40° from flat; tilt is measured from there.
            let target = CGSize(width: (attitude.roll / 0.5).clamped(to: -1...1),
                                height: ((attitude.pitch - 0.7) / 0.5).clamped(to: -1...1))
            tilt = CGSize(width: tilt.width + (target.width - tilt.width) * 0.12,
                          height: tilt.height + (target.height - tilt.height) * 0.12)
        }
    }

    /// Stops following the phone.
    func stop() {
        Self.manager.stopDeviceMotionUpdates()
    }
}

// MARK: - Previews

#Preview("Tessera · fronte") {
    StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica",
                fixedLight: CGSize(width: -0.3, height: -0.2))
        .padding(20)
}

#Preview("Tessera · retro") {
    StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica",
                startsFlipped: true, fixedLight: CGSize(width: 0.2, height: 0))
        .padding(20)
}

#Preview("Tessera · luce da destra") {
    StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica",
                fixedLight: CGSize(width: 0.9, height: 0.4))
        .padding(20)
}

#Preview("Tessera · ospite") {
    StudentCard(student: nil, fixedLight: .zero)
        .padding(20)
}

#Preview("Tessera · scuro") {
    StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica", fixedLight: .zero)
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}

#Preview("Tessera · giroscopio simulato") {
    // The simulator has no gyroscope: the light circles as a tilting hand would move it.
    TimelineView(.animation) { context in
        let t = context.date.timeIntervalSinceReferenceDate
        StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica",
                    fixedLight: CGSize(width: sin(t * 1.3) * 0.9, height: cos(t * 0.9) * 0.6))
            .padding(20)
    }
}

#Preview("Tessera · da girare") {
    // Live: tap to turn it over, drag to tilt it.
    StudentCard(student: .sample, subtitle: "Laurea Magistrale · Ingegneria Informatica")
        .padding(20)
}

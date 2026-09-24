import QuartzCore
import SwiftUI

/// Whether this launch has already played the tour's opening.
///
/// Outside ``FeatureTour`` because that is generic over its actions and a
/// generic type cannot hold a static — and per process rather than per view,
/// because the view is rebuilt every time the welcome comes back, which is the
/// case this exists for.
@MainActor
enum TourOpening {
    nonisolated(unsafe) static var hasPlayed = false
}

/// Everything ``FeatureTour``'s movement is made of, in one place.
///
/// Top level rather than nested in ``FeatureTour``, which is generic over the
/// actions it shows: nested, this type was a different type per instantiation,
/// and a `visualEffect` reading it captured that generic parameter's metatype —
/// which a closure that runs off the main actor may not do. Nothing here
/// depends on the actions.
struct TourFeel {
    /// How much of the screen's width one card takes.
    var cardWidth: CGFloat = 0.56
    /// A card's height as a multiple of its width.
    var aspect: CGFloat = 1.92
    /// The gap between two cards, in points.
    var spacing: CGFloat = 14
    /// What a card away from the middle shrinks to.
    var sideScale: CGFloat = 0.9
    /// What a card away from the middle fades to.
    var sideOpacity: CGFloat = 0.78
    /// How far a card away from the middle turns, in degrees.
    var sideRotation: Double = 12
    /// How far out of focus a card away from the middle goes.
    ///
    /// A little, and not more: the depth of field is what says the middle
    /// card is the one being looked at, but a wall of cards that are all
    /// soft has nothing to arrive *into*.
    var sideBlur: CGFloat = 3
    /// How far a card away from the middle sits below it, in points.
    var sideLift: CGFloat = 12
    /// Room left under the cards inside the clipped band.
    ///
    /// A band exactly as tall as a card cuts every card on the same pixel
    /// row — rounded corners, shadows and all — and that straight edge
    /// reads as a rule drawn across the screen. The clip is still needed,
    /// because the wall overflows downwards while it is arriving; it just
    /// has to fall in empty space.
    var shadowSlack: CGFloat = 44

    /// How long the wall takes to settle into place.
    ///
    /// A spring's duration rather than a curve's: the settle is asked for
    /// as ``SwiftUI/Animation/smooth(duration:extraBounce:)`` with no
    /// bounce, which is the system's own way of arriving somewhere without
    /// overshooting it — and, unlike an eased curve, it can be interrupted
    /// at speed and will carry that speed into whatever is asked next.
    var settle: Duration = .seconds(1.25)
    /// The scale the wall arrives at, before it settles to life size.
    var fromScale: CGFloat = 1.58
    // Small: the wall arrives mostly by growing down from its top edge,
    // so its top stays roughly where it will end up and only the scale
    // reads as movement. A big lift takes it off the screen and the
    // opening is a blur with nothing in it.
    /// How far above its place the wall arrives, in points.
    var fromLift: CGFloat = 62
    /// The blur radius the wall arrives out of focus at.
    var fromBlur: CGFloat = 26
    /// How much sooner the focus resolves than the movement finishes.
    ///
    /// The blur is taken off the settle raised to this power, so it is
    /// mostly gone by the time the wall is half home. Focus and position
    /// resolving on exactly the same curve reads as one flat dissolve;
    /// focus arriving first reads as a camera finding the wall and then
    /// coming to rest on it.
    var focusLead: Double = 1.7

    /// How long the row takes to cross one card, drifting.
    ///
    /// The row does not stop on a card and wait; it crosses them at an
    /// even pace, so there is never a frame where nothing is moving. Slow
    /// enough to read a card as it passes, and the eye is never asked to
    /// re-acquire a wall that has just started again.
    ///
    /// Not slower than this. A card is about 240 points, so three seconds
    /// to cross one is 80 points a second — a point and a third per frame.
    /// Much under that and the wall advances by less than a point between
    /// frames, and sub-pixel movement does not read as slow movement, it
    /// reads as a stutter.
    var secondsPerCard: Double = 3.0
    /// How long the drift takes to reach its pace from a standstill.
    ///
    /// Eased as a *speed*, over this long, rather than the row being told
    /// to go somewhere over this long. A movement that begins at its pace
    /// begins with a step in velocity, and a step in velocity is the one
    /// thing the eye reads as a jolt no matter how slow the movement is;
    /// an eased speed has no first frame to catch.
    var rampSeconds: Double = 1.6
    /// How long the row keeps still after a touch before moving on again.
    var restAfterTouch: Double = 1.2
    /// Copies of the deck laid end to end. The drift jumps back one deck
    /// every deck, so these are only runway for a finger's flick — a dozen
    /// is more than any flick reaches, and lazily built besides.
    var laps = 12

    /// How far into the settle the first word begins to arrive.
    var wordsBegin: Double = 0.4
    /// The delay between one piece of the caption and the next.
    var wordsStagger: Double = 0.085
    /// How long one piece of the caption takes to arrive.
    var wordSettle: Duration = .seconds(0.75)
    /// The blur radius each piece of the caption resolves from.
    var wordBlur: CGFloat = 14
}

/// The app's own screens, as a wall of cards that drifts past behind the
/// welcome.
///
/// Rather than a list of features, the tour shows the screens themselves — the
/// same navigation bar, the same tab bar, the same cards in the material the
/// look is set to.
///
/// ## The movement
///
/// Modelled on Apple Invites' opening, frame for frame:
///
/// 1. The wall arrives **zoomed in, lifted above its place and out of focus**,
///    as though the screen had been standing too close to it.
/// 2. It **settles** on one spring — scale, lift and focus together — with no
///    bounce at the end. The focus resolves a little ahead of the movement, so
///    the wall is already readable while it is still coming to rest, which is
///    what makes the settle read as depth rather than as a blur wearing off.
/// 3. It **keeps moving**: an even drift across the cards rather than a step
///    to the next and a wait on it, so there is never a frame in which the
///    wall is standing still. It is a real scroll view — a finger can join
///    the drift at any point, and it picks up again once it is let go, from
///    wherever the finger left it, easing back up to the same pace.
/// 4. The **ground is the wall itself**, blurred past recognition — a wash
///    that takes its colour from whatever card is in the middle, blended with
///    the next one's in the proportion the row is between them, so it slides
///    for the whole crossing rather than stepping when a card arrives.
/// 5. The **words come out of the blur** once the wall is nearly still, a
///    piece at a time rather than all at once, each on its own spring.
///
/// ## The drift is integrated, not animated
///
/// The drift is not an animation the scroll view is asked to run. It is a
/// position integrated from a speed, one frame at a time, off the display's
/// own clock (``TourDrive``), and written to the scroll view unanimated.
///
/// That is the whole difference between this and a long `withAnimation`. A
/// leg of animation has to end, and the next one starts from a standstill the
/// eye can see; a leg cannot be joined by a finger without being cancelled
/// mid-curve; and a leg long enough to hide its joins is a single interpolation
/// the system may re-time or drop under load. Integrating means there are no
/// legs: the speed is a value that can be eased *as a speed*, so taking off
/// after a touch is a ramp in velocity rather than a jump to it, and a finger
/// arriving only has to stop the integration.
///
/// ## Driven by the scroll view, not beside it
///
/// There is no second copy of where the row is. `onScrollGeometryChange`
/// reports where the row actually is, in points and in cards, on every frame
/// of both the drift and a drag, and that is what the ground is coloured from
/// and what the drift re-synchronises to whenever a finger has had it.
///
/// It is reported into an observable box rather than into `@State`, so the
/// frame-by-frame colour change invalidates the ground alone and not the wall
/// of cards above it.
///
/// Nothing snaps. The drift is a position in points, not a card, because a
/// movement that never stops has no reason to prefer the places where cards
/// happen to line up.
///
/// The row is finite but has no end: every deck's worth of drift, the cursor
/// jumps back one deck. The cards repeat exactly, so the frame after the jump
/// is the frame before it, and a dozen laps is enough runway for any flick.
///
/// ## Drawn, not photographed
///
/// Each card is built from the app's own components rather than from a
/// screenshot. A screenshot goes stale the week after it is taken, carries one
/// colour scheme and one language, and cannot follow Personalizza. These are
/// rebuilt every render, so they are in the reader's language, their light or
/// dark, and the look in use. The content is fixed and illustrative: during
/// the first run there is no account, so there is nothing real to draw.
struct FeatureTour<Actions: View>: View {

    /// The movement's measurements, which a preview can change.
    var feel = TourFeel()

    /// The old spelling, so `FeatureTour.Feel` still names it.
    typealias Feel = TourFeel
    /// The welcome under the wall. Fixed, as in the reference: the cards say
    /// what the app does, the words say what it is.
    var overline: LocalizedStringKey = "Ti diamo il benvenuto in"
    /// The name, revealed a word at a time.
    var title: String = "PoliVerse"
    /// The line under the name, revealed last.
    var detail: LocalizedStringKey = "Quello che oggi cerchi tra Servizi Online e WeBeep, in un'app sola — che ti avvisa prima che tu debba controllare."
    /// What the screen asks for, revealed on the same curve as the words: in
    /// the reference the button arrives with them rather than waiting sharp
    /// under a screen that is still out of focus.
    @ViewBuilder var actions: Actions

    /// 0 while the wall is still arriving, 1 once it is home.
    ///
    /// Already home when the opening has been played once this launch: the
    /// re-entry must not render even a single frame at zero, or the wall
    /// flashes zoomed and out of focus before the task that settles it runs.
    @State private var arrival: CGFloat = TourOpening.hasPlayed ? 1 : 0
    /// How many pieces of the caption have been asked for so far. Each one is
    /// a spring of its own, started a stagger after the one before it.
    @State private var revealed: Int = TourOpening.hasPlayed ? .max : 0
    /// Where the row is, as the scroll view's own position rather than a
    /// number kept beside it: the same value a finger writes and the drift
    /// reads, so the two never disagree about which card is in the middle.
    @State private var position = ScrollPosition(idType: Int.self)
    /// Where the row is, read off the scroll geometry as it moves — under a
    /// finger and under the drift alike. A box rather than `@State`, so the
    /// ground can follow it every frame without the wall being rebuilt.
    @State private var motion = TourMotion()
    /// The frame clock the drift is integrated on.
    @State private var drive = TourDrive()
    /// Whether the row has been put on its starting card yet.
    @State private var placed = false

    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The deck, in the order it is laid out.
    private let screens = TourScreen.all

    /// Where the row starts: the first screen, in the middle lap, so there is
    /// as much row to the left as to the right.
    private var start: Int { screens.count * (feel.laps / 2) }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cardWidth = size.width * feel.cardWidth
            let cardHeight = cardWidth * feel.aspect

            ZStack(alignment: .top) {
                TourBackdrop(motion: motion, screens: screens, style: style, scheme: scheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    wall(size: size, cardWidth: cardWidth, cardHeight: cardHeight)
                        // In front of the words, not behind them. A stack
                        // draws its children in order, so by default the
                        // caption and the buttons are painted over the wall —
                        // and the wall arrives at half again its size, hanging
                        // well down into the half of the screen they occupy.
                        // Behind them, the opening is the top of a card with
                        // text sitting on it; in front, the wall passes over
                        // the words on its way down to its place, which is the
                        // depth the arrival is made of.
                        .zIndex(1)
                    words
                        .padding(.horizontal, 28)
                    Spacer(minLength: 0)
                    actions
                        .modifier(Reveal(shown: revealed > lastPiece + 1, blur: feel.wordBlur))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .task { await arrive() }
        .onDisappear { drive.stop() }
    }

    // MARK: - The wall

    /// The wall of cards: a horizontal scroll view the drift and a finger both write to.
    ///
    /// - Parameters:
    ///   - size: The room the tour has.
    ///   - cardWidth: One card's width.
    ///   - cardHeight: One card's height.
    /// - Returns: The wall, clipped to its band.
    private func wall(size: CGSize, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let stride = cardWidth + feel.spacing

        return ScrollView(.horizontal) {
            LazyHStack(spacing: feel.spacing) {
                ForEach(0..<screens.count * feel.laps, id: \.self) { index in
                    TourCard(screen: screens[index % screens.count], size: CGSize(width: cardWidth, height: cardHeight))
                        .frame(width: cardWidth, height: cardHeight)
                        // The cards either side shrink, fade, turn away, sit a
                        // little lower and go a little soft — one depth of
                        // field rather than four separate effects.
                        //
                        // Measured in cards off the middle, not in screens.
                        // `scrollTransition` hands out a phase that runs from
                        // -1 to 1 across the whole visible width, so with two
                        // and a half cards on screen a card is already most of
                        // the way transformed while it is still the one in the
                        // middle, and the wall dips out of focus every time
                        // the centre falls in a gap. Off the card's own
                        // distance from the middle, divided by one stride, the
                        // card in the middle is sharp and full size for as
                        // long as it is the card in the middle.
                        //
                        // A visual effect rather than a transition, besides,
                        // because it is a transform applied from geometry on
                        // every frame: it does not rebuild the card to do it.
                        .modifier(TourDepth(feel: feel, centre: size.width / 2, stride: stride))
                }
            }
            .scrollTargetLayout()
        }
        // No snapping: a row that clicks onto a card has to stop to do it,
        // and stopping is the one thing this movement does not do. A finger
        // that lets go coasts and rests wherever it rests, and the drift
        // picks up from there rather than tidying it to a card first.
        .scrollPosition($position, anchor: .center)
        .contentMargins(.horizontal, (size.width - cardWidth) / 2, for: .scrollContent)
        .scrollIndicators(.hidden)
        // Shadows reach past the row; the room under it is where they fall.
        .scrollClipDisabled()
        // Nothing of the system's own edge treatment: the wall is a picture
        // behind the welcome, not a list running under a bar.
        .scrollEdgeEffectHidden()
        .frame(height: cardHeight + feel.shadowSlack, alignment: .top)
        // Where the row is, in points and in cards, on every frame it moves —
        // under a finger and under the drift alike. This is what the ground
        // follows, which is why its colour slides between two cards instead of
        // snapping when one arrives, and what the drift re-synchronises to
        // after a finger has moved the row out from under it.
        .onScrollGeometryChange(for: CGPoint.self) { geometry in
            CGPoint(x: geometry.contentOffset.x, y: geometry.contentInsets.leading)
        } action: { _, moved in
            print("TOURTEST x", moved.x, CACurrentMediaTime())
            guard stride > 0 else { return }
            motion.offset = moved.x
            motion.cards = (moved.x + moved.y) / stride
            // The drift only ever integrates from where the row truly is:
            // while a finger has it, the cursor follows rather than leads.
            if !drive.isDrifting { drive.cursor = moved.x }
        }
        .onScrollPhaseChange { _, phase in
            print("TOURTEST phase", phase)
            // The row's own drift is written unanimated and so is reported as
            // `.idle`: only a finger, or the coast after one, is a touch.
            drive.isHeld = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .onAppear {
            place(stride: stride)
        }
        .onChange(of: stride) { _, new in
            // A rotation changes what a card's worth of drift measures.
            drive.stride = new
            drive.wrapBy = CGFloat(screens.count) * new
        }
        // The arrival: one spring carrying scale, lift and focus together,
        // with the focus resolving a little ahead of the rest.
        .scaleEffect(feel.fromScale + (1 - feel.fromScale) * arrival, anchor: .top)
        .offset(y: -feel.fromLift * (1 - arrival))
        .blur(radius: feel.fromBlur * CGFloat(pow(Double(1 - arrival), feel.focusLead)))
        .opacity(Double(min(arrival * 2.2, 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Le schermate di PoliVerse"))
    }

    /// Puts the row on its starting card and hands the drift everything it
    /// needs to integrate: the stride, the pace, and where to jump back to.
    ///
    /// - Parameter stride: One card and the gap after it.
    private func place(stride: CGFloat) {
        guard !placed, stride > 0 else { return }
        placed = true
        position.scrollTo(id: start, anchor: .center)
        motion.cards = CGFloat(start)

        drive.stride = stride
        drive.pace = Double(stride) / feel.secondsPerCard
        drive.rampSeconds = feel.rampSeconds
        drive.restSeconds = feel.restAfterTouch
        drive.wrapBy = CGFloat(screens.count) * stride
        drive.apply = { x in position.scrollTo(x: x) }
    }

    // MARK: - The words

    /// The caption: overline, name and description, each coming out of the blur in turn.
    private var words: some View {
        VStack(spacing: 6) {
            Text(overline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .modifier(Reveal(shown: revealed > 0, blur: feel.wordBlur))

            // Word by word, out of the blur, as the reference reveals its own
            // name: the last word is still resolving while the first is sharp.
            HStack(spacing: 8) {
                ForEach(Array(title.split(separator: " ").enumerated()), id: \.offset) { index, word in
                    Text(String(word))
                        .modifier(Reveal(shown: revealed > index + 1, blur: feel.wordBlur))
                }
            }
            .font(.largeTitle.weight(.bold))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .modifier(Reveal(shown: revealed > lastPiece, blur: feel.wordBlur))
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    /// The piece after the last word of the title: the description.
    private var lastPiece: Int { title.split(separator: " ").count + 1 }

    // MARK: - Driving it

    /// Plays the opening, once per launch, then hands the row to the drift.
    ///
    /// Reduced motion and a replay both put the wall straight home.
    private func arrive() async {
        // The opening plays once. Coming back to the welcome from the sign-in
        // step is not an opening: replaying it leaves a second and a half of
        // out-of-focus wash where the screen the student just asked for should
        // be, and makes back feel slower than forward for no reason. The wall
        // is simply already home.
        guard !reduceMotion, !TourOpening.hasPlayed else {
            arrival = 1
            revealed = .max
            if !reduceMotion { drive.start() }
            return
        }
        TourOpening.hasPlayed = true

        // Sprung rather than eased, with the bounce taken out: the same family
        // of movement the system uses everywhere else, so the wall arrives the
        // way a sheet does, and an interruption keeps its speed instead of
        // restarting a curve.
        withAnimation(.smooth(duration: feel.settle.seconds, extraBounce: 0)) { arrival = 1 }

        // The words begin while the wall is still settling, a piece at a time,
        // each on a spring of its own.
        try? await Task.sleep(for: .seconds(feel.settle.seconds * feel.wordsBegin))
        for piece in 0...(lastPiece + 1) {
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: feel.wordSettle.seconds, extraBounce: 0)) { revealed = piece + 1 }
            try? await Task.sleep(for: .seconds(feel.wordsStagger))
        }

        // Only once the wall is home. A wall that starts drifting while it is
        // still growing and still out of focus is two movements at once, and
        // neither is legible.
        guard !Task.isCancelled else { return }
        print("TOURTEST start", drive.cursor)
        let x0 = drive.cursor
        withAnimation(.timingCurve(0.42, 0, 0.7, 0.4, duration: 1.6)) { position.scrollTo(x: x0 + 64) } completion: {
            print("TOURTEST join")
            withAnimation(.linear(duration: 50)) { position.scrollTo(x: x0 + 64 + 4000) }
        }
    }
}

// MARK: - The movement

/// Where the row is, as the scroll view last reported it.
///
/// Observable rather than `@State` on the tour, because it changes on every
/// frame of the drift: kept here, the ground behind the wall is the only thing
/// that reads it, and so the only thing rebuilt when it moves.
@MainActor
@Observable
final class TourMotion {
    /// Where the row is, in points.
    var offset: CGFloat = 0
    /// Where the row is, in cards, including the fraction between two.
    var cards: CGFloat = 0
}

/// The drift: a position integrated from a speed, one display frame at a time.
///
/// Not an animation. Each frame it advances a cursor by the speed it is
/// currently travelling at and writes that to the scroll view unanimated,
/// which means the movement has no legs to join, can be joined by a finger at
/// any point, and can be eased *in velocity* rather than in position — so
/// taking off after a touch has no first frame the eye can catch.
@MainActor
final class TourDrive: NSObject {
    /// One card and the gap after it, in points.
    var stride: CGFloat = 0
    /// The pace the drift settles at, in points a second.
    var pace: Double = 0
    /// How long the drift takes to reach that pace from a standstill.
    var rampSeconds: Double = 1.6
    /// How long the row keeps still after a touch before moving on again.
    var restSeconds: Double = 1.2
    /// How far the cursor runs before it jumps back: one deck.
    var wrapBy: CGFloat = 0
    /// Where the drift has carried the row to, in points.
    var cursor: CGFloat = 0
    /// What to do with the cursor: write it to the scroll view.
    var apply: ((CGFloat) -> Void)?

    /// Whether a finger has the row, or it is still coasting from one.
    ///
    /// Setting it stops the drift at once, and starts the rest that has to
    /// pass before it takes over again.
    var isHeld = false {
        didSet {
            guard isHeld != oldValue else { return }
            if isHeld { speed = 0; ramp = 0 } else { rest = restSeconds }
        }
    }

    /// Whether the drift is the one moving the row right now, as opposed to a
    /// finger, the coast after one, or the pause that follows.
    var isDrifting: Bool { link != nil && !isHeld && rest <= 0 }

    /// How far into the ramp up to pace the drift is, from 0 to 1.
    private var ramp: Double = 0
    /// The speed the row is travelling at this frame, in points a second.
    private var speed: Double = 0
    /// What is left of the rest after a touch, in seconds.
    private var rest: Double = 0
    /// How far the cursor has run since it last jumped back.
    private var run: CGFloat = 0
    /// The display's clock.
    private var link: CADisplayLink?
    /// The timestamp of the frame before this one.
    private var last: CFTimeInterval = 0

    /// Starts the drift.
    func start() {
        guard link == nil else { return }
        last = 0
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        // The drift is slow and even, which is exactly the case a variable
        // refresh rate gets wrong on its own: asked for nothing in particular
        // it will settle the display low and the movement will show its steps.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops the drift and lets go of the clock.
    func stop() {
        link?.invalidate()
        link = nil
        speed = 0
        ramp = 0
    }

    /// One frame of the display's clock.
    ///
    /// - Parameter link: The clock, which carries the frame's timestamp.
    @objc private func frame(_ link: CADisplayLink) {
        // A frame's worth of time, and never more than a couple: coming back
        // from the background hands over a gap of seconds, and integrating
        // that would teleport the row.
        let now = link.timestamp
        let elapsed = last > 0 ? min(now - last, 1.0 / 30) : 0
        last = now
        guard elapsed > 0, stride > 0, pace > 0 else { return }

        // A finger has it: the cursor is following the row, not leading it.
        guard !isHeld else { return }
        if rest > 0 {
            rest -= elapsed
            return
        }

        // Eased as a speed. Smoothstepped, so the drift leaves a standstill
        // with no acceleration to notice and arrives at its pace with none
        // either — the two places a ramp can show a seam.
        ramp = min(ramp + elapsed / max(rampSeconds, 0.01), 1)
        speed = pace * (ramp * ramp * (3 - 2 * ramp))
        cursor += CGFloat(speed * elapsed)
        run += CGFloat(speed * elapsed)

        // A deck's worth of drift, and back one deck. The cards repeat
        // exactly, so the frame after the jump draws what the frame before it
        // drew, and the row has run without ever reaching an end.
        if wrapBy > 0, run >= wrapBy {
            run -= wrapBy
            cursor -= wrapBy
        }
        apply?(cursor)
    }
}

/// A piece of the caption coming out of the blur.
///
/// The arrival is a state, not a progress: each piece is given its own spring
/// when its turn comes, so the pieces are genuinely staggered rather than one
/// curve sampled at different points, and an interruption leaves each of them
/// wherever it had got to.
private struct Reveal: ViewModifier {
    /// Whether this piece has been asked to arrive.
    let shown: Bool
    /// The blur radius the piece resolves from.
    let blur: CGFloat

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        content
            .blur(radius: shown ? 0 : blur)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            // Barely: enough that the words arrive *towards* the reader rather
            // than sliding up into place, which is the difference between the
            // reference's reveal and a list animating its rows in.
            .scaleEffect(shown ? 1 : 0.96, anchor: .top)
    }
}

/// The ground: the wall of cards blurred past recognition.
///
/// The reference builds it from the artwork of the card in the middle, so the
/// screen is bathed in that card's colour and changes with it. Here the colour
/// comes from the same place the card's own accent does.
///
/// It reads the drift straight off ``TourMotion``, so the only thing rebuilt
/// on a frame of the drift is this — the wall of cards above it is untouched.
private struct TourBackdrop: View {
    /// Where the row is, which is what the wash is coloured from.
    let motion: TourMotion
    /// The deck, whose accents the wash is mixed from.
    let screens: [TourScreen]
    /// The look in use, which supplies the accents.
    let style: TodayStyle
    /// Whether the interface is in light or dark mode.
    let scheme: ColorScheme

    /// The view's content.
    var body: some View {
        let cards = motion.cards
        let accent = middleAccent(at: cards)
        // A hair of travel in the pools, against the row: the ground is the
        // wall out of focus, and a wall out of focus does not hold still while
        // the wall in focus moves. Small, and in the opposite direction, so it
        // reads as distance rather than as a second thing scrolling.
        let sway = CGFloat((cards - cards.rounded(.down)) - 0.5) * 0.04

        ZStack {
            Color(.systemBackground)
            // Three soft pools rather than one flat fill: a single colour
            // reads as a painted wall, and what this stands for is a photograph
            // out of focus.
            RadialGradient(colors: [accent.opacity(0.55), .clear],
                           center: .init(x: 0.2 - sway, y: 0.18), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [accent.opacity(0.4), .clear],
                           center: .init(x: 0.9 - sway, y: 0.32), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [accent.opacity(0.28), .clear],
                           center: .init(x: 0.5 - sway, y: 0.78), startRadius: 0, endRadius: 520)
        }
        // No blur pass, and no animation. The colour arrives a frame at a
        // time off the scroll itself, and three radial gradients are already
        // as soft as a blur would make them: blurring them would cost a
        // full-screen offscreen pass every frame to change almost nothing,
        // and animating a value that moves every frame would start a new
        // animation every frame to chase a number that has already arrived.
        .accessibilityHidden(true)
    }

    /// The colour the ground takes: the accent of whichever card is in the
    /// middle right now — and, while the row is between two, the mix of
    /// theirs, in the proportion the row is between them. A card arriving
    /// does not change the wash; crossing towards it does, the whole way.
    ///
    /// - Parameter cards: Where the row is, in cards.
    /// - Returns: The colour to wash the ground in.
    private func middleAccent(at cards: CGFloat) -> Color {
        let leaving = Int(cards.rounded(.down))
        let raw = Double(cards - CGFloat(leaving))
        // Eased across the crossing rather than mixed linearly: a linear mix
        // of two colours spends the middle of the crossing in a muddy third
        // colour and changes fastest exactly where the eye is on it. Smooth-
        // stepped, the wash holds each card's own colour while that card is
        // the one being looked at, and turns over in between.
        let crossed = raw * raw * (3 - 2 * raw)
        let from = accent(ofCard: leaving), to = accent(ofCard: leaving + 1)
        return Color(.sRGB,
                     red: from.red + (to.red - from.red) * crossed,
                     green: from.green + (to.green - from.green) * crossed,
                     blue: from.blue + (to.blue - from.blue) * crossed)
    }

    /// The accent of one place in the repeated row, whichever lap it is on,
    /// flattened to the colour it actually is in this mode.
    ///
    /// Flattened here rather than mixed as `Color`s, because the accents are
    /// dynamic — a closure the system calls with the traits — and the wash
    /// feeds gradients the renderer may resolve off the main thread, which a
    /// main-actor closure does not survive. Resolving on this side of the
    /// line hands the gradient a plain colour and keeps the crossing ours.
    ///
    /// - Parameter index: A place in the repeated row.
    /// - Returns: That card's accent, as components.
    private func accent(ofCard index: Int) -> (red: Double, green: Double, blue: Double) {
        let wrapped = ((index % screens.count) + screens.count) % screens.count
        let color = screens[wrapped].accent(style: style, scheme: scheme)
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}

/// Reading a duration as the seconds an animation is asked for.
private extension Duration {
    /// The duration in seconds.
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

// MARK: - The screens

/// One card of the deck: a screen of the app and the line that names it.
struct TourScreen: Identifiable, Sendable {
    /// Which screen of the app a card stands for.
    enum Kind: String, Sendable { case today, courses, career, rooms, look }

    /// The screen this card draws.
    let kind: Kind
    /// The card's headline.
    let title: LocalizedStringKey
    /// The line under it.
    let detail: LocalizedStringKey

    /// The card's identity, which is its kind.
    var id: String { kind.rawValue }

    /// What the card is called, in the capsule in its top corner.
    var badge: LocalizedStringKey {
        switch kind {
        case .today: "Oggi · apri e sai già tutto"
        case .courses: "Corsi · tutto in un posto"
        case .career: "Carriera · la media, prima"
        case .rooms: "Cerca · tutto il Politecnico"
        case .look: "Personalizza · solo tua"
        }
    }

    /// Glass icons floating over the wash, as the reference floats its
    /// guests' faces: the things this part of the app deals in.
    var clusterSymbols: [String] {
        switch kind {
        case .today: ["clock.fill", "mappin.and.ellipse", "calendar", "bell.fill", "graduationcap.fill"]
        case .courses: ["doc.fill", "play.rectangle.fill", "books.vertical.fill", "bubble.left.fill", "tray.full.fill"]
        case .career: ["chart.bar.fill", "checkmark.seal.fill", "function", "bell.badge.fill", "list.bullet.rectangle"]
        case .rooms: ["door.left.hand.open", "map.fill", "building.2.fill", "magnifyingglass", "person.2.fill"]
        case .look: ["paintbrush.fill", "textformat", "paintpalette.fill", "sparkles", "square.on.square"]
        }
    }

    /// The SF Symbol in the capsule in the card's top corner.
    var badgeSymbol: String {
        switch kind {
        case .today: "calendar.day.timeline.left"
        case .courses: "books.vertical.fill"
        case .career: "graduationcap.fill"
        case .rooms: "magnifyingglass"
        case .look: "paintbrush.fill"
        }
    }

    /// The colour this screen lends the ground behind the wall.
    ///
    /// The look's own accent for the screens the look colours, and the
    /// course's palette for the ones that carry a subject's colour: the
    /// reference takes the ground from the card in the middle, and these are
    /// where each card's colour comes from.
    @MainActor
    func accent(style: TodayStyle, scheme: ColorScheme) -> Color {
        switch kind {
        case .today, .look, .career: style.palette(scheme).accent
        case .courses: Theme.courseAccents[2]
        case .rooms: .green
        }
    }

    /// The five cards, in the order the tour lays them out.
    static let all: [TourScreen] = [
        TourScreen(kind: .today,
                   title: "Sai già dove andare",
                   detail: "La prossima lezione, l'aula e quanto manca: appena apri l'app, nel widget e sulla schermata di blocco."),
        TourScreen(kind: .courses,
                   title: "Un corso, non tre siti",
                   detail: "Orari, appelli e materiali di WeBeep dello stesso corso, sulla stessa pagina."),
        TourScreen(kind: .career,
                   title: "La media, prima del voto",
                   detail: "Simula come cambia la media con il prossimo esame, e ricevi un avviso appena esce un esito."),
        TourScreen(kind: .rooms,
                   title: "Un'aula libera, adesso",
                   detail: "Corsi, docenti e aule da un solo campo, e dove studiare adesso: quale aula è libera e fino a quando."),
        TourScreen(kind: .look,
                   title: "Non somiglia a nessun'altra",
                   detail: "Colore, carattere e materiale per tutta l'app; sfondo e adesivi per la tua giornata."),
    ]
}

/// A screen drawn at card size: the app's chrome around a page of its own.
/// One screen of the app, drawn at card size.
///
/// No tab bar: the bar is the same on every screen, so five cards carrying it
/// spend a fifth of their height saying the same thing five times. What names
/// the card is the badge in its top corner, as the reference does it.
private struct TourCard: View {
    /// The screen this card draws.
    let screen: TourScreen
    /// The card's size, which the page inside is scaled to.
    let size: CGSize

    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The corner of a phone, scaled to the card.
    private var corner: CGFloat { size.width * 0.12 }

    /// The card's own colour, which the ground behind the wall also takes.
    private var accent: Color { screen.accent(style: style, scheme: scheme) }

    /// The view's content.
    var body: some View {
        // The screen is the card's picture, as the photo is in the reference:
        // it fills the card, and the words sit on a wash of the card's own
        // colour rising from the bottom.
        VStack(spacing: 0) {
            page
                .padding(.horizontal, 12)
                .padding(.top, 50)
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(ground)
        // The lower part of the card under thick, tinted glass, fading in
        // from clear so the screen above still reads as the card's picture.
        // The glass begins at the middle of the main icon, so the cluster
        // sits half on the screen and half on the glass, as the reference's
        // faces sit half on the photo.
        .overlay(alignment: .bottom) {
            let side = size.width * 0.13
            let cluster = side * 1.9
            VStack(spacing: -cluster / 2) {
                TourIconCluster(symbols: screen.clusterSymbols, accent: accent, side: side)
                    .zIndex(1)
                caption
                    .padding(.top, cluster / 2 + 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        Rectangle()
                            .fill(.regularMaterial)
                            .overlay(accent.opacity(0.45))
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.22),
                                .init(color: .black, location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                            // Reaches a little above the icons' middle, so the
                            // blur feathers in instead of starting on a line.
                            .padding(.top, -side * 0.75)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            TourBadge(symbol: screen.badgeSymbol, title: screen.badge)
                .padding(.top, 14)
                .padding(.leading, 12)
        }
        .clipShape(.rect(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .allowsHitTesting(false)
    }

    /// Title and one line under it, centred and white, as the reference sets
    /// its event name over the photo.
    private var caption: some View {
        VStack(spacing: 5) {
            Text(screen.title)
                .font(.system(size: size.width * 0.095, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(screen.detail)
                .font(.system(size: size.width * 0.048))
                .opacity(0.82)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    /// Oggi and Personalizza carry the look's paper and decoration; the rest
    /// do not, because in the app they do not either — the look travels by
    /// colour, type and material, and the page's own ground is Oggi's alone.
    /// A tour that decorated every card would be promising something the app
    /// does not do.
    @ViewBuilder
    private var ground: some View {
        if screen.kind == .today || screen.kind == .look {
            TodayBackgroundView(style: style)
        } else {
            Color(.systemBackground)
        }
    }

    /// The page drawn inside the card's chrome, by kind.
    @ViewBuilder
    private var page: some View {
        switch screen.kind {
        case .today: TourToday()
        case .courses: TourCourses()
        case .career: TourCareer()
        case .rooms: TourRooms()
        case .look: TourLook()
        }
    }
}

// MARK: - Chrome

/// A loose cluster of glass circles, the middle one largest and filled with
/// the card's colour — the reference's avatars, as the section's own symbols.
private struct TourIconCluster: View {
    /// The five symbols to cluster, middle one largest.
    let symbols: [String]
    /// The colour the middle circle is filled with.
    let accent: Color
    /// The middle circle's side, which the others are scaled from.
    let side: CGFloat

    // Offsets and sizes fixed by position, so every card clusters the same way.
    /// Each circle's offset and size, in multiples of ``side``.
    private let layout: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-1.55, 0.25, 0.8), (-0.8, -0.35, 0.85), (0, 0.1, 1.3), (0.85, -0.3, 0.85), (1.6, 0.3, 0.8),
    ]

    /// The view's content.
    var body: some View {
        ZStack {
            ForEach(Array(symbols.prefix(layout.count).enumerated()), id: \.offset) { index, symbol in
                let place = layout[index]
                let middle = index == 2
                Image(systemName: symbol)
                    .font(.system(size: side * place.scale * 0.42, weight: .semibold))
                    .foregroundStyle(middle ? Color.white : accent)
                    .frame(width: side * place.scale, height: side * place.scale)
                    .background { if middle { Circle().fill(accent) } }
                    .glassEffect(middle ? .regular.tint(accent) : .regular, in: .circle)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .offset(x: place.x * side, y: place.y * side)
                    .zIndex(middle ? 1 : 0)
            }
        }
        .frame(height: side * 1.9)
        .accessibilityHidden(true)
    }
}

/// What this card is, in its top corner: a glass capsule with a symbol and a
/// word, as the reference labels each of its own.
private struct TourBadge: View {
    /// The badge's SF Symbol.
    let symbol: String
    /// The badge's word.
    let title: LocalizedStringKey

    /// The view's content.
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(title).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityHidden(true)
    }
}

/// The blocks the pages are built from, at card scale.
private struct TourCardBlock<Content: View>: View {
    /// The content this view wraps.
    @ViewBuilder let content: Content

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookCard(cornerRadius: 14)
    }
}

/// A section heading inside a card, at card scale.
private struct TourHeading: View {
    /// The heading.
    let text: LocalizedStringKey

    /// The view's content.
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
    }
}

/// A list row inside a card, at card scale.
private struct TourRow: View {
    /// The row's leading SF Symbol.
    let symbol: String
    /// The row's first line.
    let title: String
    /// The row's second line.
    let detail: String
    /// What sits at the row's trailing edge, such as a mark.
    var trailing: String?
    /// The symbol's colour; a neutral one when left out.
    var tint: Color?
    /// A capsule after the title, such as a room.
    var badge: String?

    /// The view's content.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.tint, in: .capsule)
            }
            if let trailing {
                Text(trailing).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }
}

// MARK: - The pages

/// Oggi as the app opens it, in the look in use: the date in its typeface, the next lessons and the student's own stickers.
private struct TourToday: View {
    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Buona giornata!").font(.system(size: 10, weight: .medium))
            // The date in the look's own typeface and weight: this is the one
            // thing on the page that is unmistakably the student's choice.
            // Two lines, not one string with a break: a negative line spacing
            // on a single Text made it truncate to "17.09…" in wide faces.
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: -4) {
                    Text(verbatim: "17.09")
                    Text(verbatim: "GIO")
                }
                .font(style.dateFont.font(size: 32, weight: style.dateWeight))
                .foregroundStyle(style.dateTint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize()

                // The panel beside the date, as Oggi has it: what makes the
                // page read as someone's own rather than a template.
                StickerPanel(stickers: stickers, outline: style.stickerOutline)
                    .frame(height: 58)
            }

            TourHeading(text: "In arrivo")
            TourCardBlock {
                TourRow(symbol: "graduationcap.fill", title: "Prova in itinere — Analisi 2",
                        detail: "Aula Magna", trailing: "16 ore", tint: Theme.brand)
                CardDivider(inset: 30)
                TourRow(symbol: "graduationcap.fill", title: "Ingegneria del Software 2",
                        detail: "Aula Magna", trailing: "2 sett.", tint: Theme.brand)
                CardDivider(inset: 30)
                TourRow(symbol: "tray.full.fill", title: "Consegna — Reti Logiche",
                        detail: "WeBeep", trailing: "3 gg", tint: .orange)
            }

            TourHeading(text: "Orario")
            VStack(spacing: 5) {
                lesson("Basi di Dati", "10:15 – 13:00 · Lab Informatico", filled: true)
                lesson("Automatica", "14:15 – 16:00 · Aula De Donato", filled: false)
            }
        }
    }

    /// The student's own stickers when the look has some — someone replaying
    /// the tour from Settings sees their page — and three placed by hand
    /// otherwise, landed where Personalizza would land them.
    private var stickers: [PlacedSticker] {
        style.accessory == .stickers && !style.stickers.isEmpty ? style.stickers : Self.sampleStickers
    }

    /// Three stickers placed where Personalizza would place them, for a look that has none.
    private static let sampleStickers: [PlacedSticker] = {
        var look = TodayStyle()
        for emoji in ["☕️", "📚", "✨"] { look.addSticker(.emoji(emoji)) }
        return look.stickers
    }()

    /// One lesson row on the Oggi card.
    ///
    /// - Parameters:
    ///   - title: The course's name.
    ///   - detail: Its time and room.
    ///   - filled: True for the next lesson, which is drawn in the accent.
    /// - Returns: The row.
    private func lesson(_ title: String, _ detail: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill").font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .semibold))
                Text(detail).font(.system(size: 8)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(filled ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(Color.primary))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint)
            }
        }
        .modifier(TourPlainCard(on: !filled))
    }
}

/// A row that sits on the look's material when it is not filled with colour.
private struct TourPlainCard: ViewModifier {
    /// Whether to put the row on the look's material.
    let on: Bool

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        if on { content.lookCard(cornerRadius: 12) } else { content }
    }
}

/// A course's own page — Basi di Dati — drawn as CourseDetailView draws it:
/// the glass tile in the course's colour, its name and facts, then lessons,
/// the next sitting and the materials. Full size, scaled into the card.
private struct TourCourses: View {
    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The course the card is about, taken from the sample degree.
    private let course = Course.samples.first { $0.name == "Basi di Dati" } ?? Course.samples[0]

    /// The view's content.
    var body: some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        let accent = Theme.accent(for: course)
        GeometryReader { proxy in
            let scale: CGFloat = 0.56
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 10) {
                    GlassTile(symbol: SubjectSymbol.symbol(for: course.name), colour: ramp.main, side: 96,
                              surface: .glass, mode: ramp.mode)
                        .padding(.bottom, 6)
                    Text(course.name).font(.title.weight(.bold))
                    Text(verbatim: "Stefano Ceri · 10 CFU · 1° semestre")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label("Prossimo appello tra 19 giorni", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)

                block("Lezioni") {
                    row("clock", "Lunedì · 10:15 – 13:00", "Aula Rogers", accent)
                    CardDivider(inset: 52)
                    row("clock", "Giovedì · 14:15 – 16:00", "Lab Informatico", accent)
                }
                block("Appelli") {
                    row("pencil.and.list.clipboard", "Scritto e orale · 6 ott", "Iscrizioni aperte", accent)
                }
                block("Materiali") {
                    row("doc.fill", "Lezione 12 — Transazioni", "PDF · 2,4 MB", .red)
                    CardDivider(inset: 52)
                    row("play.rectangle.fill", "Registrazione 08/10", "1h 48m", .purple)
                }
            }
            .padding(.horizontal, 20)
            .frame(width: proxy.size.width / scale, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .allowsHitTesting(false)
    }

    /// A titled block on the courses card.
    ///
    /// - Parameters:
    ///   - title: The block's heading.
    ///   - content: Its rows.
    /// - Returns: The block.
    private func block<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LookHeading(title)
            VStack(spacing: 0) { content() }.lookCard()
        }
    }

    /// One material row on the courses card.
    ///
    /// - Parameters:
    ///   - symbol: The file's symbol.
    ///   - title: Its name.
    ///   - detail: Its size or date.
    ///   - tint: The symbol's colour.
    /// - Returns: The row.
    private func row(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// Carriera drawn at card scale: the average, the credits, and the last few results.
private struct TourCareer: View {
    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                stat(value: "27.40", label: "Media", big: true)
                stat(value: "100", label: "Base su 110", big: true)
            }

            TourCardBlock {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Crediti").font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(verbatim: "108 / 180 CFU").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: 0.6).tint(Theme.brand).scaleEffect(y: 0.7, anchor: .center)
                    Text(verbatim: "60% del piano di studi")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                .padding(9)
            }

            HStack(spacing: 7) {
                stat(value: "18", label: "Esiti", big: false)
                stat(value: "2", label: "Iscrizioni", big: false)
                stat(value: "26", label: "Insegn.", big: false)
            }

            TourHeading(text: "Ultimi esiti")
            TourCardBlock {
                TourRow(symbol: "checkmark.seal.fill", title: "Geometria e Algebra",
                        detail: "12 CFU · 14 feb", trailing: "30L", tint: .green)
                CardDivider(inset: 30)
                TourRow(symbol: "checkmark.seal.fill", title: "Analisi Matematica 2",
                        detail: "10 CFU · 3 feb", trailing: "28", tint: .green)
                CardDivider(inset: 30)
                TourRow(symbol: "clock.fill", title: "Basi di Dati",
                        detail: "Iscritto · 6 ott", trailing: "—", tint: .orange)
            }
        }
    }

    /// One figure and its label, on the look's card.
    ///
    /// - Parameters:
    ///   - value: The figure.
    ///   - label: What it counts.
    ///   - big: True for the two headline figures.
    /// - Returns: The tile.
    private func stat(value: String, label: LocalizedStringKey, big: Bool) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: big ? 19 : 14, weight: .bold))
                .foregroundStyle(.tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, big ? 9 : 7)
        .lookCard(cornerRadius: 12)
    }
}

/// Cerca, drawn with the search tab's own pieces — its kind chips and its
/// place tiles — at the size the tab draws them, then scaled into the card.
private struct TourRooms: View {
    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The place tiles the search tab offers, as name, subtitle and symbol.
    private let places: [(String, String, String)] = [
        ("Calendario", "Settimana e mese", "calendar"),
        ("Aule libere", "Adesso e più tardi", "door.left.hand.open"),
        ("Mappa del campus", "Campus ed edifici", "map"),
        ("Piano di studi", "Piano e simulazione", "list.bullet.rectangle"),
    ]

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let scale: CGFloat = 0.56
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Corsi, docenti, aule, notizie…")
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

                VStack(alignment: .leading, spacing: 10) {
                    LookHeading("Cerca tra")
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Array(SearchView.Kind.allCases.prefix(3)), id: \.self) { kind in
                                Label(kind.title, systemImage: kind.symbol)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    LookHeading("Vai a")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(places, id: \.0) { place in
                            PlaceTile(title: Text(place.0), detail: Text(place.1), symbol: place.2,
                                      colour: FlavorRamp(style: style, scheme: scheme)
                                        .colour(at: Double(TodayDigest.colourIndex(for: place.2)) / 7))
                        }
                    }
                }
            }
            .frame(width: proxy.size.width / scale, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// Personalizza as the app opens it: the look's own page on top, and the
/// real Bento panel under it — the same tiles, drawn by the same code — at
/// full size, scaled into the card.
private struct TourLook: View {
    /// The look in use, which supplies the colours, typeface and material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let scale: CGFloat = 0.56
            let width = proxy.size.width / scale
            VStack(spacing: 0) {
                DateHeader(day: .now, style: style, size: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                BentoPanel(style: .constant(style), path: .constant([]),
                           arranging: .constant(false), detent: .constant(.large))
                    .frame(height: proxy.size.height / scale)
                    .background(.background, in: .rect(cornerRadius: 30))
            }
            .frame(width: width, alignment: .top)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Tour") {
    FeatureTour {
        OnboardingPrimaryButton(title: "Accedi con account Polimi") {}
            .padding(.horizontal, 28)
    }
    .previewEnvironment()
}

/// The depth of field across the wall: the cards either side of the middle
/// shrink, fade, turn away, sit a little lower and go a little soft.
///
/// A modifier of its own rather than a `visualEffect` written inline, because
/// `visualEffect`'s closure runs off the main actor and so may capture nothing
/// non-`Sendable`. Written inside ``FeatureTour`` it captured that view's
/// generic parameter's metatype, which is not one. Nothing here is generic, so
/// there is nothing to capture.
private struct TourDepth: ViewModifier {
    /// The tuning the look supplies.
    let feel: TourFeel
    /// The middle of the band, in the scroll view's own space.
    let centre: CGFloat
    /// One card plus the gap after it: distance is measured in cards off the
    /// middle, not in screens.
    let stride: CGFloat

    /// The card, transformed by how far off the middle it is.
    ///
    /// - Parameter content: The card.
    /// - Returns: The transformed card.
    func body(content: Content) -> some View {
        content.visualEffect { [feel, centre, stride] content, proxy in
            let middle = proxy.frame(in: .scrollView(axis: .horizontal)).midX
            let away = min(abs(middle - centre) / max(stride, 1), 1)
            // Eased rather than linear in distance: the middle card holds its
            // size across the few points either side of centre, so the card
            // being looked at is not visibly shrinking the whole time it is
            // there.
            let depth = away * away * (3 - 2 * away)
            let turn = (middle - centre) / max(stride, 1)
            return content
                .scaleEffect(1 - (1 - feel.sideScale) * depth)
                .opacity(1 - (1 - feel.sideOpacity) * depth)
                .offset(y: feel.sideLift * depth)
                .blur(radius: feel.sideBlur * depth)
                .rotation3DEffect(.degrees(max(min(turn, 1), -1) * feel.sideRotation),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        }
    }
}

struct TestDrift: CustomAnimation {
    var pace: Double, ramp: Double, distance: Double
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let x = min(time / ramp, 1)
        var d = pace * ramp * (x*x*x - x*x*x*x/2)
        if time > ramp { d += pace * (time - ramp) }
        if d >= distance { return nil }
        return value.scaled(by: d / distance)
    }
}

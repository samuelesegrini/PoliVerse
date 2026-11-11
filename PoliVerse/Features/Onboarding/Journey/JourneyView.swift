import SwiftUI
import UserNotifications

/// The first-run landscape, account linking and additional settings.
/// The sequence and cursor live in JourneyFlow and OnboardingState.
struct JourneyView: View {
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``WhatsNewState``, from the environment.
    @Environment(WhatsNewState.self) private var whatsNew
    /// The look in use, coloured by the atmosphere step.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The final page’s offset during the button-triggered reveal.
    @State private var pull: CGFloat = 0
    /// Whether the card is on its way off, after which nothing may pull it.
    @State private var isEntering = false
    /// Which way the last move went, so the pages slide the right way.
    ///
    /// Held here and set a frame before the step changes: the page leaving
    /// takes its transition from the last frame it was drawn in, so a
    /// direction set in the same frame as the move would reach only the page
    /// arriving, and going back would push the old page out the wrong side.
    @State private var isMovingBack = false

    /// What the journey knows right now. Rebuilt on every render, since signing in
    /// changes it.
    private var context: JourneyFlow.Context {
        #if DEBUG
        if CommandLine.arguments.contains("-PreviewOnboarding") {
            return JourneyFlow.Context(
                isSignedIn: ![JourneyFlow.Step.welcome, .intents, .preview, .signIn].contains(step))
        }
        #endif
        return JourneyFlow.Context(
            isSignedIn: session.student != nil,
            isDemo: session.useMockData,
            notificationsDenied: notifications.authorization == .denied)
    }

    /// The step on screen.
    private var step: JourneyFlow.Step { onboarding.journeyStep }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                // Over the app, while it waits underneath the last page.
                if step == .ready {
                    Color.black
                        .opacity(0.3 * (1 - min(pull / 420, 1)))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                page(height: height, width: proxy.size.width, insets: proxy.safeAreaInsets)
                    .offset(y: pull)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.88), value: step)
        .sensoryFeedback(.selection, trigger: step)
    }

    /// The landscape, edge to edge, and the step over it: everything that moves
    /// when the last page is pulled down.
    private func page(height: CGFloat, width: CGFloat, insets: EdgeInsets) -> some View {
        ZStack(alignment: .top) {
            JourneyLandscape(palette: palette)
            VStack(spacing: 0) {
                topBar
                content(height: height)
                    // One geometry for the whole page: what a step lays out a
                    // beat late — the pills behind a ViewThatFits — otherwise
                    // appears in place while the rest of the page slides in.
                    .geometryGroup()
                    .id(step)
                    .transition(stepTransition(width: width))
            }
            .padding(.horizontal, 24)
            // The page is the whole screen, so it keeps clear of the status
            // bar and the home indicator itself.
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom + 8)
        }
        // Square while it is the whole screen; the corners come in as it is
        // pulled away, so it reads as a page leaving rather than a sliding wall.
        .clipShape(.rect(cornerRadius: min(pull * 0.35, 48), style: .continuous))
        .ignoresSafeArea()
        .simultaneousGesture(swipeBack, isEnabled: JourneyFlow.canGoBack(from: step, in: context))
    }

    /// Back navigation, without a progress indicator.
    private var topBar: some View {
        HStack(spacing: 12) {
            if JourneyFlow.canGoBack(from: step, in: context) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(JourneyDisc())
                }
                .buttonStyle(JourneyPress())
                .accessibilityLabel("Torna al passo precedente")
                .accessibilityIdentifier("onboarding-back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(height: 44)
    }

    /// The step's own content.
    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        switch step {
        case .welcome:
            JourneyWelcome(start: advance) { move(back: false) { onboarding.jumpJourney(to: .signIn) } }
        case .intents:
            #if DEBUG
            if JourneyFeaturesPrototype.isEnabled {
                JourneyFeaturesPrototype(chapter: .day, advance: advance)
            } else {
                JourneyIntents(advance: advance)
            }
            #else
            JourneyIntents(advance: advance)
            #endif
        case .preview:
            #if DEBUG
            if JourneyFeaturesPrototype.isEnabled {
                JourneyFeaturesPrototype(chapter: .study, advance: advance)
            } else {
                JourneyPreview(advance: advance, change: back)
            }
            #else
            JourneyPreview(advance: advance, change: back)
            #endif
        case .signIn:
            JourneySignIn(advance: advance)
        case .connections:
            JourneyConnections(advance: advance)
        case .studies:
            JourneyStudies(advance: advance)
        case .reminders:
            JourneyReminders(advance: advance)
        case .atmosphere:
            JourneyAtmosphere(flavor: flavorBinding, advance: advance)
        case .ready:
            JourneyReady { enter(height: height) }
        }
    }

    /// The landscape for the step: a day passing, then the student's colour.
    private var palette: JourneyPalette {
        switch step {
        case .welcome: .dawn
        case .intents: .meadow
        case .preview:
            #if DEBUG
            JourneyFeaturesPrototype.isEnabled ? .lake : .meadow
            #else
            .meadow
            #endif
        case .signIn, .connections, .studies: .lake
        case .reminders: .sunset
        case .atmosphere, .ready: .flavor(style.flavor)
        }
    }

    /// Pages swipe across the whole screen: forward, the old one leaves to the left
    /// as the new one comes in from the right; back, the other way. A cross-fade
    /// under reduced motion.
    ///
    /// By the screen's width rather than the page's own, which is inset: moved
    /// only by itself, the leaving page would stop with a strip still showing.
    ///
    /// - Parameter width: The screen's width.
    private func stepTransition(width: CGFloat) -> AnyTransition {
        if reduceMotion { return .opacity }
        let ahead = isMovingBack ? -width : width
        return .asymmetric(insertion: .offset(x: ahead), removal: .offset(x: -ahead))
    }

    /// The look's colour, written to the look in use and to the saved look it is.
    ///
    /// Written as the student picks rather than on Continua: the app's tint follows
    /// the look, so the whole screen answers the choice, not only the landscape.
    private var flavorBinding: Binding<Flavor> {
        Binding { style.flavor } set: { flavor in
            applyToLook { $0.flavor = flavor }
        }
    }

    /// Moves to the next step that applies.
    private func advance() {
        let next = JourneyFlow.next(after: step, in: context)
        // Before the app is drawn under the last card: its first task shows
        // what is new, and on a first run there is nothing to be new against.
        if next == .ready || next == nil { whatsNew.adoptFirstRun() }
        move(back: false) { onboarding.advanceJourney(in: context) }
    }

    /// Steps back, where the journey allows it.
    private func back() {
        move(back: true) { onboarding.goBackInJourney(in: context) }
    }

    /// Sets the direction, then moves on the next frame when the direction changed,
    /// so the page leaving slides the new way too.
    ///
    /// - Parameters:
    ///   - back: Whether the move goes back.
    ///   - change: The move itself.
    private func move(back: Bool, _ change: @escaping () -> Void) {
        guard isMovingBack != back else {
            change()
            return
        }
        isMovingBack = back
        Task { @MainActor in change() }
    }

    /// A swipe from left to right goes back, as it does everywhere else on iOS.
    private var swipeBack: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let across = value.translation.width, down = value.translation.height
                if across > 90, across > abs(down) * 1.5 { back() }
            }
    }

    /// Finishes onboarding and reveals the app from the bottom button.
    ///
    /// - Parameter height: How far the card has to travel to be gone.
    private func enter(height: CGFloat) {
        guard !isEntering else { return }
        isEntering = true
        whatsNew.adoptFirstRun()
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .smooth(duration: 0.5)) {
            pull = height + 40
        } completion: {
            onboarding.complete()
        }
    }

    /// Changes the look in use and, when the saved looks hold it, that saved copy
    /// too — otherwise Personalizza would open on the look as it was and put it back.
    ///
    /// - Parameter change: What to change.
    private func applyToLook(_ change: (inout TodayStyle) -> Void) {
        change(&style)
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: TodayStyle.libraryKey) ?? ""
        guard !stored.isEmpty else { return }
        var library = LookLibrary.load(defaults)
        var updated = library.active
        change(&updated)
        library.save(updated, at: library.selection)
        library.persist(to: defaults)
    }
}

// MARK: - Previews

#Preview("Journey") {
    JourneyView().previewEnvironment()
}

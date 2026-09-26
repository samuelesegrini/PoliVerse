import SwiftUI

/// The first run: a full-screen landscape that passes from dawn to the colour the
/// student picks, asking what the app is for before it asks for the account.
///
/// ## Why this replaced ``OnboardingView``
///
/// The old flow was right about what to ask and wrong about when: its second screen
/// was the Politecnico's login, before the student had seen anything of theirs. Here
/// the account is the fourth step. First the student says what they are here for,
/// sees the Oggi those answers make on sample data, and only then connects it —
/// "Rendila mia" rather than "Accedi".
///
/// ``OnboardingView`` and its steps are kept, unused, until this has been lived with.
///
/// The sequence is ``JourneyFlow``; where it has got to is ``OnboardingState``, which
/// outlives this view when signing in swaps it out.
struct JourneyView: View {
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``WhatsNewState``, from the environment.
    @Environment(WhatsNewState.self) private var whatsNew
    /// The look in use, which the atmosphere step colours and the ready step orders.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the last card has been pulled down.
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
        JourneyFlow.Context(
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
                // A handle only where the page can be pulled.
                if step == .ready {
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: 60, height: 5)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
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
        .gesture(pullDown(height: height), isEnabled: step == .ready && !isEntering)
        .simultaneousGesture(swipeBack, isEnabled: JourneyFlow.canGoBack(from: step, in: context))
    }

    /// The back button, where the journey allows one, and the line that says how far
    /// through the journey is.
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
            // Not on the welcome: nothing has started yet.
            if step != .welcome {
                JourneyProgress(fraction: progress.fraction, label: progress.label)
            } else {
                Spacer()
            }
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(height: 44)
    }

    /// How far through the journey the step on screen is.
    ///
    /// Counted over the steps that apply now, so choosing the sample data, which
    /// drops the reminders, moves the line on rather than leaving a gap.
    private var progress: (fraction: Double, label: String) {
        let steps = JourneyFlow.steps(in: context)
        guard let index = steps.firstIndex(of: step), steps.count > 1 else { return (0, "") }
        return (Double(index) / Double(steps.count - 1),
                String(localized: "Passo \(index + 1) di \(steps.count)"))
    }

    /// The step's own content.
    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        switch step {
        case .welcome:
            JourneyWelcome(start: advance) { move(back: false) { onboarding.jumpJourney(to: .signIn) } }
        case .intents:
            JourneyIntents(advance: advance)
        case .preview:
            JourneyPreview(advance: advance, change: back)
        case .signIn:
            JourneySignIn(advance: advance)
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
        case .intents, .preview: .meadow
        case .signIn, .studies: .lake
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

    /// The pull that takes the last card off the app.
    ///
    /// - Parameter height: How far the card has to travel to be gone.
    private func pullDown(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let distance = value.translation.height
                // Upwards resists, like a sheet already at its top.
                pull = distance < 0 ? distance * 0.15 : distance
            }
            .onEnded { value in
                if value.translation.height > 170 || value.predictedEndTranslation.height > 420 {
                    enter(height: height)
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { pull = 0 }
                }
            }
    }

    /// Sets the app up as the journey decided and takes the card away.
    ///
    /// - Parameter height: How far the card has to travel to be gone.
    private func enter(height: CGFloat) {
        guard !isEntering else { return }
        isEntering = true
        applyToLook { $0.lead(with: JourneyFlow.leadingSections(for: onboarding.intents)) }
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
        var looks = TodayStyle.library(from: stored, active: style)
        let selection = defaults.integer(forKey: TodayStyle.selectionKey)
        guard looks.indices.contains(selection) else { return }
        change(&looks[selection])
        defaults.set(TodayStyle.encodeLibrary(looks), forKey: TodayStyle.libraryKey)
    }
}

// MARK: - Previews

#Preview("Journey") {
    JourneyView().previewEnvironment()
}

import SwiftUI

// The seven steps of ``JourneyView``. Each is only its content: the card, the
// landscape and the back button belong to the journey.

// MARK: - Welcome

/// What PoliVerse is, in four real fragments rather than a list of features.
struct JourneyWelcome: View {
    /// Starts the questions.
    let start: () -> Void
    /// Goes straight to the account, for someone who has used the app before.
    let signIn: () -> Void

    /// Whether the fragments have dropped in.
    @State private var shown = false
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                moment(.timetable, "Analisi 2", angle: -5, alignment: .leading, index: 0)
                moment(.rooms, "Aula libera", angle: 4, alignment: .trailing, index: 1)
                moment(.recordings, "Reti logiche", angle: 3, alignment: .leading, index: 2)
                moment(.average, "La tua media", angle: -3, alignment: .trailing, index: 3)
            }
            .padding(.top, 8)
            .accessibilityHidden(true)
            Spacer(minLength: 20)
            JourneyTitle(resource: "Tutto il Poli,\nin una _tasca._")
            JourneyNote(text: "App non ufficiale, fatta da studenti.")
                .padding(.top, 10)
            Spacer(minLength: 20)
            JourneyAction(title: "Iniziamo", action: start)
            JourneyLink(title: "Ho già un account", identifier: "onboarding-signin", action: signIn)
                .padding(.top, 4)
        }
        .onAppear { shown = true }
    }

    /// One fragment, tilted, dropping in after the one before.
    private func moment(_ intent: JourneyFlow.Intent, _ text: LocalizedStringKey, angle: Double,
                        alignment: Alignment, index: Int) -> some View {
        HStack(spacing: 10) {
            intent.avatar(side: 42)
            Text(text)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(JourneyInk.ink)
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .journeyCream()
        .rotationEffect(.degrees(angle))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: alignment)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -40)
        .animation(reduceMotion ? .easeOut(duration: 0.2)
                   : .spring(response: 0.6, dampingFraction: 0.62).delay(0.15 + Double(index) * 0.12),
                   value: shown)
    }
}

// MARK: - Intents

/// "A cosa ti serve?": the answers every later step reads.
struct JourneyIntents: View {
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Moves the journey on.
    let advance: () -> Void

    /// How far each pill sits off centre, so the column reads as placed by hand.
    private let offsets: [CGFloat] = [-6, 8, -10, 6, -4, 4]

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "A cosa ti _serve_ PoliVerse?")
                .padding(.bottom, 20)
            ViewThatFits(in: .vertical) {
                pills(font: .title, avatar: 50, spacing: 14)
                pills(font: .title2, avatar: 42, spacing: 10)
                ScrollView { pills(font: .title2, avatar: 42, spacing: 10) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            // Offered the room before the spacer, which would otherwise take
            // half of it and push the pills down a size.
            .layoutPriority(1)
            Spacer(minLength: 16)
            if onboarding.intents.isEmpty {
                JourneyNote(text: "Scegline quante vuoi")
                    .frame(height: 56)
            } else {
                JourneyAction(title: "Continua", action: advance)
            }
        }
    }

    /// The six answers, at a size.
    private func pills(font: Font.TextStyle, avatar: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(JourneyFlow.Intent.allCases.enumerated()), id: \.element) { index, intent in
                JourneyPill(isOn: onboarding.intents.contains(intent)) {
                    toggle(intent)
                } leading: {
                    intent.avatar(side: avatar)
                } label: {
                    Text(intent.title)
                        .font(.system(font, design: .rounded, weight: .heavy))
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .offset(x: offsets[index])
                .accessibilityIdentifier("onboarding-intent-\(intent.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Adds or removes an answer. "Boh… per Tutto" lights the others one after
    /// another, top to bottom; taking any one away takes it off again.
    private func toggle(_ intent: JourneyFlow.Intent) {
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.62)
        if intent == .everything, !onboarding.intents.contains(.everything) {
            for (index, each) in JourneyFlow.Intent.allCases.enumerated() {
                withAnimation(spring.delay(Double(index) * 0.09)) { _ = onboarding.intents.insert(each) }
            }
            return
        }
        withAnimation(spring) {
            if onboarding.intents.contains(intent) {
                onboarding.intents.remove(intent)
                onboarding.intents.remove(.everything)
            } else {
                onboarding.intents.insert(intent)
            }
        }
    }
}

// MARK: - Preview

/// The Oggi the answers make: a row for each answer taken, and the others as chips
/// underneath. New containers rather than the pills of the step before, dropping in
/// one after another.
struct JourneyPreview: View {
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Moves the journey on.
    let advance: () -> Void
    /// Goes back to change the answers.
    let change: () -> Void

    /// Whether the rows have dropped in.
    @State private var shown = false
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The answers taken, as the concrete ones.
    private var chosen: [JourneyFlow.Intent] { JourneyFlow.expanded(onboarding.intents) }
    /// The answers not taken.
    private var others: [JourneyFlow.Intent] { JourneyFlow.Intent.concrete.filter { !chosen.contains($0) } }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "Ecco la _tua_ Oggi")
                .padding(.bottom, 20)
            VStack(spacing: 12) {
                ForEach(Array(chosen.enumerated()), id: \.element) { index, intent in
                    let sample = Self.sample(intent)
                    JourneyCard(title: Text(sample.title), detail: Text(sample.detail)) {
                        intent.avatar()
                    }
                    .dropIn(shown, index: index, reduceMotion: reduceMotion)
                }
                if !others.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(others) { intent in chip(intent) }
                    }
                    .padding(.top, 4)
                    .dropIn(shown, index: chosen.count, reduceMotion: reduceMotion)
                    JourneyNote(text: "Le altre restano, solo più in basso.")
                        .dropIn(shown, index: chosen.count + 1, reduceMotion: reduceMotion)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 16)
            JourneyNote(text: "Dati di esempio: diventano tuoi quando accedi.")
                .padding(.bottom, 12)
            JourneyAction(title: "Rendila mia", action: advance)
            JourneyLink(title: "Cambia scelte", identifier: "onboarding-change", action: change)
                .padding(.top, 4)
        }
        .onAppear { shown = true }
    }

    /// An answer not taken, as a small dashed chip.
    private func chip(_ intent: JourneyFlow.Intent) -> some View {
        HStack(spacing: 8) {
            intent.avatar(side: 34)
            Text(Self.shortName(intent))
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .lineLimit(1)
                .fixedSize()
                .journeyVibrant()
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .journeyDashed()
    }

    /// What each answer looks like on a day, on the sample data. The answers that
    /// live outside Oggi say where they live.
    private static func sample(_ intent: JourneyFlow.Intent) -> (title: LocalizedStringKey, detail: LocalizedStringKey) {
        switch intent {
        case .timetable: ("Analisi 2 · tra 25 min", "10:15 · Aula B.2.4")
        case .exams: ("Fisica tecnica", "Iscrizioni: chiudono domani")
        case .recordings: ("2 lezioni da recuperare", "Reti logiche · in Corsi")
        case .rooms: ("Aula 3.1.2 libera", "Fino alle 14 · in Cerca")
        case .average, .everything: ("Media ponderata 27,4", "In Carriera")
        }
    }

    /// The one-word name of an answer, for its chip.
    private static func shortName(_ intent: JourneyFlow.Intent) -> LocalizedStringKey {
        switch intent {
        case .timetable: "Orario"
        case .exams: "Esami"
        case .recordings: "Video"
        case .rooms: "Aule"
        case .average, .everything: "Media"
        }
    }
}

private extension View {
    /// Drops in from above after the ones before it, or fades under reduced motion.
    ///
    /// - Parameters:
    ///   - shown: Whether it has come in.
    ///   - index: Its place in the order of arrival.
    ///   - reduceMotion: Whether the reader has asked for reduced motion.
    func dropIn(_ shown: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : -36)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                       : .spring(response: 0.55, dampingFraction: 0.72).delay(0.25 + Double(index) * 0.08),
                       value: shown)
    }
}

// MARK: - Sign-in

/// The account, now that there is something of the student's to connect it to.
///
/// The ways in are ``PoliMiSignInButton``'s, in a sheet: the choice between codice
/// persona, SPID and CIE is the same one ``LoginView`` offers, and the promise that
/// no credential is typed here is kept by that file. Career and WeBeep follow as
/// sheets over this step, only when they apply.
struct JourneySignIn: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Moves the journey on.
    let advance: () -> Void

    /// Whether the ways in are showing.
    @State private var showingMethods = false
    /// The sheet that follows the sign-in, when one applies.
    @State private var followUp: FollowUp?
    /// Whether the sample data is being loaded.
    @State private var isLoadingSample = false

    /// What may follow the sign-in.
    enum FollowUp: String, Identifiable {
        /// More than one enrolment.
        case career
        /// Recordings asked for, and WeBeep not connected.
        case weBeep
        /// The raw value.
        var id: String { rawValue }
    }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "Ora colleghiamo il _tuo_ Poli")
                .padding(.bottom, 24)
            VStack(spacing: 12) {
                promise("lock.fill", "La password non la vediamo", "Si scrive sulla pagina del Poli")
                promise("iphone", "Resta sul telefono", "Non c'è un server di PoliVerse")
                promise("eye.slash.fill", "Niente tracciamento", "Né statistiche, né account")
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 16)
            if case .exchangingCode = session.state {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Accesso in corso…")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                }
                .foregroundStyle(JourneyInk.ink)
                .padding(.horizontal, 22)
                .frame(height: 56)
                .journeyCream()
            } else {
                JourneyNote(text: "Codice persona, SPID o CIE")
                    .padding(.bottom, 12)
                JourneyAction(title: "Accedi con Polimi", symbol: "key.fill", disc: Flavor.polimi.base.color) {
                    // Explicit: the account route turns the sample data off, so
                    // nobody signs in and still reads invented lectures.
                    session.useMockData = false
                    showingMethods = true
                }
                JourneyLink(title: "Continua con i dati di esempio", identifier: "onboarding-demo") {
                    guard !isLoadingSample else { return }
                    isLoadingSample = true
                    Task {
                        session.useMockData = true
                        await session.login.restore()
                        isLoadingSample = false
                        advance()
                    }
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingMethods) {
            JourneyMethodsSheet()
        }
        // Back from a career switch: signed out on purpose, so straight to the
        // ways in, where the sign-in lands on the matricola just chosen.
        .task(id: session.student == nil) {
            guard onboarding.reopensSignIn, session.student == nil else { return }
            onboarding.reopensSignIn = false
            try? await Task.sleep(for: .milliseconds(400))
            showingMethods = true
        }
        .sheet(item: $followUp) { followUp in
            switch followUp {
            case .career: JourneyCareerSheet { proceed(after: .career) }
            case .weBeep: JourneyWeBeepSheet { proceed(after: .weBeep) }
            }
        }
        // The token arriving is the only thing that moves this step on — the
        // id changes at exactly that moment, and it covers a replay, where the
        // session is already live.
        .task(id: session.student?.matricola) {
            guard session.student != nil, !session.useMockData else { return }
            showingMethods = false
            await careers.load()
            proceed(after: nil)
        }
    }

    /// Shows what follows the sign-in, in order, or moves on when nothing does.
    ///
    /// - Parameter done: The sheet just finished, if any.
    private func proceed(after done: FollowUp?) {
        if done == nil, careers.hasChoice {
            followUp = .career
            return
        }
        if done != .weBeep, JourneyFlow.offersWeBeep(for: onboarding.intents), !weBeep.isAuthenticated {
            followUp = .weBeep
            return
        }
        followUp = nil
        advance()
    }

    /// One promise, dashed: said, not chosen.
    private func promise(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(JourneyDisc())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.headline, design: .rounded, weight: .heavy))
                Text(detail).font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .journeyVibrant()
        }
        .padding(.leading, 8)
        .padding(.trailing, 22)
        .padding(.vertical, 8)
        .journeyDashed()
        .accessibilityElement(children: .combine)
    }
}

/// A cream sheet, always light: its ink is dark whatever the system says.
private struct JourneySheetStyle: ViewModifier {
    /// The modified content.
    func body(content: Content) -> some View {
        // No foreground style here: the sign-in buttons inside keep their own.
        content
            .presentationBackground(JourneyInk.cream)
            .presentationCornerRadius(44)
            .environment(\.colorScheme, .light)
    }
}

/// The ways into the Politecnico.
private struct JourneyMethodsSheet: View {
    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Come entri?")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                Text("Si apre la pagina del Politecnico o del tuo gestore: la password si scrive lì, mai qui.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JourneyInk.inkSoft)
                    .multilineTextAlignment(.center)
                PoliMiSignInButton()
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .modifier(JourneySheetStyle())
    }
}

/// Which enrolment the app is pointed at, when there is more than one.
///
/// The token is bound to the matricola the student signed in with, so choosing
/// another one is a new sign-in: the same switch Impostazioni · Matricola makes —
/// the favourite set while this token still works, then out and back in on it. The
/// journey stays on the sign-in step and opens the ways in again by itself.
private struct JourneyCareerSheet: View {
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Moves on.
    let done: () -> Void

    /// The career picked, when it is not the one in use.
    @State private var picked: Career?
    /// True while switching.
    @State private var switching = false

    /// The matricola the session is on.
    private var inUse: String? { session.student?.matricola }

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Hai più di una carriera")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("Scegli quella da usare. Il Poli risponde per una matricola alla volta.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JourneyInk.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                ForEach(careers.careers) { career in
                    row(career)
                }
                if picked != nil {
                    Text("Per cambiare matricola serve un nuovo accesso: si riapre la pagina del Poli, questa volta su quella scelta.")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(JourneyInk.inkSoft)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if let picked {
                    JourneyAction(title: "Passa a questa", symbol: "arrow.triangle.2.circlepath", isBusy: switching) {
                        switchCareer(to: picked)
                    }
                    .padding(.top, 12)
                } else {
                    JourneyAction(title: "Continua con questa", symbol: "checkmark") {
                        // Remembered so the mismatch banner knows this was a choice.
                        if let current = careers.current { careers.remember(current) }
                        done()
                    }
                    .padding(.top, 12)
                }
            }
            .padding(24)
            .animation(.snappy, value: picked?.matricola)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
        .modifier(JourneySheetStyle())
    }

    /// One career: cream and checked when it is the one chosen, dashed otherwise.
    private func row(_ career: Career) -> some View {
        let chosen = (picked?.matricola ?? inUse) == career.matricola
        return Button {
            picked = career.matricola == inUse ? nil : career
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(career.matricola)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                    Text(career.label)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(JourneyInk.inkSoft)
                    if career.matricola == inUse {
                        Text("Quella dell'accesso")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(JourneyInk.action)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(JourneyInk.action))
                    } else {
                        Circle()
                            .strokeBorder(Color(white: 0.6), lineWidth: 2.4)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .foregroundStyle(JourneyInk.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                if chosen {
                    Capsule().fill(.white).shadow(color: .black.opacity(0.08), radius: 10, y: 6)
                } else {
                    Capsule().strokeBorder(Color(white: 0.72), style: StrokeStyle(lineWidth: 1.6, dash: [8, 7]))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(JourneyPress())
        .disabled(switching)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: chosen)
    }

    /// Moves the account to another enrolment, as ``CareerSwitchView`` does.
    ///
    /// - Parameter career: The enrolment to land on.
    private func switchCareer(to career: Career) {
        switching = true
        Task {
            // Order matters: the favourite must be set while the current token
            // still works. After signing out there is nothing to sign it with.
            careers.remember(career)
            await careers.markFavourite(career)
            // Back on the sign-in step, the ways in open by themselves.
            onboarding.reopensSignIn = true
            await session.login.beginCareerRelogin(matricola: career.matricola)
            switching = false
        }
    }
}

/// WeBeep, offered only to someone who came for the recordings: they live there,
/// behind a sign-in of their own.
private struct JourneyWeBeepSheet: View {
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// Moves on.
    let done: () -> Void

    /// Whether WeBeep's own sign-in is up.
    @State private var showingLogin = false

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                JourneyFlow.Intent.recordings.avatar(side: 76)
                    .padding(.bottom, 4)
                Text("I Video stanno su WeBeep")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("Hai scelto i Video: WeBeep ha un accesso tutto suo. Lo fai una volta, e lezioni e dispense si scaricano anche offline.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JourneyInk.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                JourneyAction(title: "Collega WeBeep", symbol: "link", disc: Flavor.RGB(hex: "#6A45C4")!.color) {
                    showingLogin = true
                }
                Button("Più tardi", action: done)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(JourneyInk.inkSoft)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding-skip")
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
        .modifier(JourneySheetStyle())
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet {
                await courses.load(force: true)
                done()
            }
        }
    }
}

// MARK: - Reminders

/// Which reminders, shown as the notifications they would be, before the permission
/// iOS only asks for once.
struct JourneyReminders: View {
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Moves the journey on.
    let advance: () -> Void

    /// Which groups are on, seeded from the answers.
    @State private var groups: JourneyFlow.ReminderGroups?
    /// Whether the notifications have dropped in.
    @State private var shown = false
    /// True while iOS's prompt is up.
    @State private var isAsking = false
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The groups as they stand.
    private var current: JourneyFlow.ReminderGroups {
        groups ?? JourneyFlow.reminders(for: onboarding.intents)
    }

    /// Whether any group is on.
    private var anyOn: Bool { current.lectures || current.exams || current.weBeep }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "Ti avvisiamo _noi_")
                .padding(.bottom, 24)
            VStack(spacing: 12) {
                reminder(.timetable, "Lezioni", "«Analisi 2 tra \(notifications.preferences.leadMinutes) min, aula B.2.4»",
                         isOn: current.lectures, index: 0) { $0.lectures.toggle() }
                reminder(.exams, "Esami e iscrizioni", "«Iscrizioni: ultimo giorno per Fisica tecnica»",
                         isOn: current.exams, index: 1) { $0.exams.toggle() }
                reminder(.recordings, "WeBeep", "«Nuova registrazione di Reti logiche»",
                         isOn: current.weBeep, index: 2) { $0.weBeep.toggle() }
            }
            .frame(maxWidth: .infinity)
            JourneyNote(text: "Tocca per tenere solo quelli che vuoi. Calcolati sul telefono, non escono da lì.")
                .padding(.top, 20)
            Spacer(minLength: 16)
            JourneyAction(title: anyOn ? "Attiva i promemoria" : "Continua senza", symbol: "bell.fill", isBusy: isAsking) {
                activate()
            }
            JourneyLink(title: "Non ora", action: advance)
                .padding(.top, 4)
        }
        .onAppear { shown = true }
        // iOS's prompt says nothing once it closes; the outcome is felt instead.
        .sensoryFeedback(trigger: notifications.authorization) { previous, now in
            guard previous == .notDetermined else { return nil }
            return now == .authorized ? .success : .error
        }
    }

    /// One reminder group, as an example of what it would say.
    private func reminder(_ intent: JourneyFlow.Intent, _ title: LocalizedStringKey, _ example: LocalizedStringKey,
                          isOn: Bool, index: Int, toggle: @escaping (inout JourneyFlow.ReminderGroups) -> Void) -> some View {
        JourneyPill(isOn: isOn, indicator: .check) {
            var next = current
            toggle(&next)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { groups = next }
        } leading: {
            intent.avatar(side: 46)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.headline, design: .rounded, weight: .heavy))
                Text(example)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .opacity(0.8)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rotationEffect(.degrees([-1.2, 1.2, -0.5][index]))
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -46)
        .animation(reduceMotion ? .easeOut(duration: 0.2)
                   : .spring(response: 0.6, dampingFraction: 0.6).delay(0.3 + Double(index) * 0.35),
                   value: shown)
    }

    /// Saves the groups, asks iOS when it has not been asked, and schedules.
    private func activate() {
        var preferences = notifications.preferences
        current.apply(to: &preferences)
        notifications.preferences = preferences
        guard anyOn else {
            advance()
            return
        }
        isAsking = true
        Task {
            if notifications.authorization == .notDetermined {
                await notifications.requestAuthorization()
            }
            await notifications.reschedule(
                events: agenda.events, exams: career.sessions,
                assignments: feed.deadlines, updates: feed.updates)
            isAsking = false
            advance()
        }
    }
}

// MARK: - Atmosphere

/// The look's colour. The landscape, and the app's tint, follow the pick.
struct JourneyAtmosphere: View {
    /// The look's Flavor.
    @Binding var flavor: Flavor
    /// Moves the journey on.
    let advance: () -> Void

    /// The swatches offered: the Politecnico's own, then six that read well as a
    /// landscape. The rest are in Personalizza.
    private var swatches: [Flavor.Swatch] {
        // Blu Politecnico, Lavanda, Cielo, Menta, Mandarino, Corallo, Grafite.
        [0, 1, 3, 4, 6, 7, 11].compactMap { Flavor.swatches.indices.contains($0) ? Flavor.swatches[$0] : nil }
    }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "Scegli la tua _atmosfera_")
                .padding(.bottom, 20)
            ViewThatFits(in: .vertical) {
                column(avatar: 44, font: .title2, spacing: 10)
                grid
            }
            .layoutPriority(1)
            Spacer(minLength: 16)
            JourneyNote(text: "Il colore dell'app e della tua Oggi. Il resto in Personalizza.")
                .padding(.bottom, 12)
            JourneyAction(title: "Continua", action: advance)
        }
    }

    /// The swatches in a column, each a little off centre.
    private func column(avatar: CGFloat, font: Font.TextStyle, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(swatches.enumerated()), id: \.element.id) { index, swatch in
                pill(swatch, avatar: avatar, font: font)
                    .offset(x: [-6, 8, -10, 6, -4, 4, -8][index % 7])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The swatches two by two, when a column does not fit.
    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(swatches) { swatch in pill(swatch, avatar: 34, font: .headline) }
        }
    }

    /// One swatch.
    private func pill(_ swatch: Flavor.Swatch, avatar: CGFloat, font: Font.TextStyle) -> some View {
        JourneyPill(isOn: swatch.flavor.base == flavor.base, indicator: .check) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { flavor = swatch.flavor }
        } leading: {
            JourneyAvatar(mark: .none,
                          colours: (swatch.flavor.base.blended(with: .white, 0.35).color, swatch.flavor.base.color),
                          side: avatar)
        } label: {
            Text(swatch.name)
                .font(.system(font, design: .rounded, weight: .heavy))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Ready

/// What the journey set up, and the way in: pull the card down, or tap.
struct JourneyReady: View {
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The look in use.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Takes the card away.
    let enter: () -> Void

    /// Whether the summary has dropped in.
    @State private var shown = false
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            Label("Trascina giù per entrare", systemImage: "chevron.down")
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .foregroundStyle(.white.opacity(0.95))
                .offset(y: shown && !reduceMotion ? 4 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: shown)
                .accessibilityHidden(true)
            JourneyTitle(resource: "Tutto _pronto._")
                .padding(.top, 18)
                .padding(.bottom, 24)
            VStack(spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    JourneyCard(title: line.title, detail: line.detail) { line.avatar }
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : -40)
                        .animation(reduceMotion ? .easeOut(duration: 0.2)
                                   : .spring(response: 0.6, dampingFraction: 0.62).delay(0.2 + Double(index) * 0.12),
                                   value: shown)
                }
            }
            Spacer(minLength: 16)
            JourneyNote(text: "Si cambia tutto da Impostazioni.")
                .padding(.bottom, 12)
            JourneyAction(title: "Entra in PoliVerse", symbol: "arrow.down", action: enter)
        }
        .onAppear { shown = true }
    }

    /// One line of the summary.
    private struct Line {
        /// The first line.
        let title: Text
        /// The second line.
        let detail: Text
        /// The avatar.
        let avatar: JourneyAvatar
    }

    /// What was set up, as the student would say it.
    private var lines: [Line] {
        var lines: [Line] = []
        let chosen = JourneyFlow.expanded(onboarding.intents)
        if let first = chosen.first {
            lines.append(Line(title: Text("La tua Oggi"), detail: Text("Parte da: \(Self.list(chosen))"), avatar: first.avatar()))
        }
        if session.useMockData {
            lines.append(Line(title: Text("Dati di esempio"), detail: Text("Il tuo account si collega da Impostazioni"),
                              avatar: JourneyAvatar(mark: .symbol("theatermasks.fill"), colours: (Color(white: 0.75), Color(white: 0.45)))))
        } else {
            let reminders = notifications.authorization == .authorized
            lines.append(Line(title: Text("Promemoria"),
                              detail: reminders ? Text("\(notifications.preferences.leadMinutes) minuti prima delle lezioni") : Text("Spenti, per ora"),
                              avatar: JourneyAvatar(mark: .symbol(reminders ? "bell.fill" : "bell.slash.fill"),
                                                    colours: (Flavor.RGB(hex: "#F3B18F")!.color, Flavor.RGB(hex: "#C9604A")!.color))))
            if JourneyFlow.offersWeBeep(for: onboarding.intents) || weBeep.isAuthenticated {
                lines.append(Line(title: Text(verbatim: "WeBeep"), detail: weBeep.isAuthenticated ? Text("Collegato") : Text("Da collegare, nella scheda Corsi"),
                                  avatar: JourneyFlow.Intent.recordings.avatar()))
            }
        }
        let base = style.flavor.base
        lines.append(Line(title: Text("Atmosfera"), detail: Self.swatchName(style.flavor),
                          avatar: JourneyAvatar(mark: .none, colours: (base.blended(with: .white, 0.35).color, base.color))))
        return lines
    }

    /// The answers as a short list: "orario, esami e video".
    private static func list(_ intents: [JourneyFlow.Intent]) -> String {
        let names = intents.map { intent -> String in
            switch intent {
            case .timetable: String(localized: "orario")
            case .exams: String(localized: "esami")
            case .recordings: String(localized: "video")
            case .rooms: String(localized: "aule")
            case .average, .everything: String(localized: "media")
            }
        }
        return names.formatted(.list(type: .and))
    }

    /// The swatch a Flavor is, or "Su misura" for any other colour.
    private static func swatchName(_ flavor: Flavor) -> Text {
        guard let swatch = Flavor.swatches.first(where: { $0.flavor.base == flavor.base }) else { return Text("Su misura") }
        return Text(swatch.name)
    }
}

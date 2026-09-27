import Foundation

/// The first run as a journey: who you are, then your account, then how the app
/// should look — and what each answer along the way changes.
///
/// Replaces ``OnboardingFlow`` on screen. The difference is the order: the old flow
/// asked for the account on its second screen, before the student had seen anything
/// of theirs; this one asks what the app is *for* first, shows the Oggi those answers
/// make, and only then asks to connect it. The account step is the fourth.
///
/// Pure, like ``OnboardingFlow``: the sequence is derived from a ``Context`` on every
/// query, because signing in and choosing the sample data both change it midway.
/// ``OnboardingState`` holds the cursor.
nonisolated enum JourneyFlow {
    /// One screen of the journey, in the order ``next(after:in:)`` falls forward through.
    enum Step: String, CaseIterable, Identifiable, Sendable {
        /// What the app is, in four real fragments.
        case welcome
        /// "A cosa ti serve?": the answers that shape everything after.
        case intents
        /// The Oggi those answers make, on sample data.
        case preview
        /// The Politecnico's sign-in, or the sample data.
        case signIn
        /// The degree course and approved plan (PSPA), and the favourite campus.
        case studies
        /// Which reminders, then the permission.
        case reminders
        /// The look's colour.
        case atmosphere
        /// What was set up; pulling the card down opens the app.
        case ready

        /// The raw value.
        var id: String { rawValue }
    }

    /// What the app is for, as the student says it on ``Step/intents``.
    ///
    /// Answers add up. None of them hides anything: they decide what Oggi puts first,
    /// which reminders start switched on, and whether WeBeep is offered.
    enum Intent: String, CaseIterable, Identifiable, Sendable, Codable {
        /// Lessons, and where they are.
        case timetable
        /// Sittings and enrolment windows.
        case exams
        /// Lecture recordings, which live on WeBeep.
        case recordings
        /// Free classrooms.
        case rooms
        /// The weighted average.
        case average
        /// "Boh… per Tutto": every other answer at once.
        case everything

        /// The raw value.
        var id: String { rawValue }

        /// The five answers ``everything`` stands for.
        static let concrete: [Intent] = [.timetable, .exams, .recordings, .rooms, .average]
    }

    /// What the journey knows about the account when it is asked.
    struct Context: Equatable, Sendable {
        /// Whether there is a live session.
        var isSignedIn = false
        /// Whether the student chose the sample data instead of an account.
        var isDemo = false
        /// Whether iOS has already been asked and refused: asking again shows nothing.
        var notificationsDenied = false

        /// Creates a context.
        ///
        /// - Parameters:
        ///   - isSignedIn: Whether there is a live session.
        ///   - isDemo: Whether the student chose the sample data.
        ///   - notificationsDenied: Whether notification permission was already refused.
        init(isSignedIn: Bool = false, isDemo: Bool = false, notificationsDenied: Bool = false) {
            self.isSignedIn = isSignedIn
            self.isDemo = isDemo
            self.notificationsDenied = notificationsDenied
        }
    }

    // MARK: - Sequence

    /// The steps that apply, in order.
    ///
    /// The studies step is always there: the sample data has no plan to confirm, but
    /// a campus is worth choosing either way.
    ///
    /// Reminders are dropped for the sample data — the app schedules nothing from
    /// invented lectures — and once iOS has refused. Career and WeBeep are not steps:
    /// they are sheets over ``Step/signIn``, shown only when they apply, so the
    /// sequence does not change length under the student halfway through.
    ///
    /// - Parameter context: What the journey should take into account.
    /// - Returns: The applicable steps.
    static func steps(in context: Context) -> [Step] {
        var steps: [Step] = [.welcome, .intents, .preview, .signIn, .studies]
        if !context.isDemo, !context.notificationsDenied { steps.append(.reminders) }
        steps += [.atmosphere, .ready]
        return steps
    }

    /// The step after a given one, or `nil` when the journey is over.
    ///
    /// Tolerates a step that has stopped applying by falling forward to the first
    /// later one that still does.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the journey should take into account.
    /// - Returns: The next step.
    static func next(after step: Step, in context: Context) -> Step? {
        let steps = steps(in: context)
        if let index = steps.firstIndex(of: step) {
            return steps.indices.contains(index + 1) ? steps[index + 1] : nil
        }
        guard let position = Step.allCases.firstIndex(of: step) else { return nil }
        return steps.first { Step.allCases.firstIndex(of: $0)! > position }
    }

    /// The step before a given one, or `nil` at the start.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the journey should take into account.
    /// - Returns: The preceding step.
    static func previous(before step: Step, in context: Context) -> Step? {
        let steps = steps(in: context)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// Whether a back button belongs on a step.
    ///
    /// Not back onto ``Step/signIn`` once there is a session — signing in over a live
    /// one has the identity provider replay the grant — and not back from the end,
    /// where the only way is into the app.
    ///
    /// - Parameters:
    ///   - step: The step on screen.
    ///   - context: What the journey should take into account.
    /// - Returns: `true` when the student may step back.
    static func canGoBack(from step: Step, in context: Context) -> Bool {
        guard step != .ready, let previous = previous(before: step, in: context) else { return false }
        if context.isSignedIn || context.isDemo, previous == .signIn { return false }
        return true
    }

    // MARK: - What the answers change

    /// The answers as the five concrete ones: ``Intent/everything``, or no answer at
    /// all, stands for every one.
    ///
    /// - Parameter intents: What the student chose.
    /// - Returns: The concrete answers, in their canonical order.
    static func expanded(_ intents: Set<Intent>) -> [Intent] {
        if intents.isEmpty || intents.contains(.everything) { return Intent.concrete }
        return Intent.concrete.filter(intents.contains)
    }

    /// The Oggi sections the answers put first, in order.
    ///
    /// Only answers Oggi has a section for: the lesson now and the day's timetable,
    /// and the sittings. Recordings, rooms and the average live in their own tabs and
    /// leave the page as it is.
    ///
    /// - Parameter intents: What the student chose.
    /// - Returns: The sections to lift to the top.
    static func leadingSections(for intents: Set<Intent>) -> [TodaySection.Kind] {
        expanded(intents).flatMap { intent -> [TodaySection.Kind] in
            switch intent {
            case .timetable: [.currentClass, .timetable]
            case .exams: [.exams]
            case .recordings, .rooms, .average, .everything: []
            }
        }
    }

    /// The reminder groups the answers switch on to begin with.
    ///
    /// - Parameter intents: What the student chose.
    /// - Returns: Which of the three groups start on.
    static func reminders(for intents: Set<Intent>) -> ReminderGroups {
        let chosen = expanded(intents)
        return ReminderGroups(
            lectures: chosen.contains(.timetable),
            exams: chosen.contains(.exams) || chosen.contains(.average),
            weBeep: chosen.contains(.recordings))
    }

    /// Whether WeBeep is worth offering right after signing in: only to someone who
    /// said they are here for the recordings, which is where those live.
    ///
    /// - Parameter intents: What the student chose.
    /// - Returns: `true` when the WeBeep sheet should follow the sign-in.
    static func offersWeBeep(for intents: Set<Intent>) -> Bool {
        intents.contains(.recordings) || intents.contains(.everything)
    }

    /// The three reminder groups the journey offers, each standing for several
    /// ``NotificationPreferences`` switches.
    struct ReminderGroups: Equatable, Sendable {
        /// Before each lesson.
        var lectures: Bool
        /// Sittings, enrolment windows and changes to an exam.
        var exams: Bool
        /// News from WeBeep and its hand-ins.
        var weBeep: Bool

        /// Writes the groups onto a set of preferences, leaving every other switch as
        /// it was.
        ///
        /// - Parameter preferences: The preferences to change.
        func apply(to preferences: inout NotificationPreferences) {
            preferences.lectures = lectures
            preferences.exams = exams
            preferences.enrolments = exams
            preferences.examUpdates = exams
            preferences.weBeepUpdates = weBeep
            preferences.deadlines = weBeep
        }
    }
}

nonisolated extension TodayStyle {
    /// Lifts the sections the journey's answers ask for to the top of the page,
    /// showing any that were hidden or never added, in the answers' order.
    ///
    /// - Parameter kinds: The sections to put first, from
    ///   ``JourneyFlow/leadingSections(for:)``.
    mutating func lead(with kinds: [TodaySection.Kind]) {
        guard !kinds.isEmpty else { return }
        for kind in kinds { addSection(kind) }
        let target = sections.first { !kinds.contains($0.kind) }?.kind
        moveSections(kinds, before: target)
    }
}

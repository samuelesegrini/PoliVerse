import SwiftUI

/// What a colour means on Carriera.
///
/// One table for the whole area, so the exam sheet, the updates feed and the
/// sittings list cannot disagree about what a colour means, and no colour ends
/// up doing duty for several unrelated things at once — a colour that means
/// four things means none.
///
/// One axis decides all of them: **what the state asks of the student.**
///
/// | | | |
/// |---|---|---|
/// | `enrolmentOpen` | orange | a clock on something you must *do* |
/// | `refusable` | purple | a clock on something you may *undo* |
/// | `passed` | green | an outcome that stands |
/// | `failed` | red | an outcome that did not |
/// | `booked` | the look's colour | settled with the Politecnico |
/// | `dormant` | secondary | nothing is being asked |
///
/// Purple is the odd one and earns it: a refusable mark is the only state
/// that is *both* an outcome and a deadline, so it cannot sit in either
/// family without being mistaken for the other. It is also the only hue left
/// once green and red are spoken for by outcomes, orange by deadlines and the
/// accent by the student's own look.
///
/// Every use pairs the colour with a word and a symbol, so nothing here is
/// carried by hue alone — which is what keeps the green/red pair legible to
/// the third of people who would otherwise read them as the same colour.
nonisolated enum CareerState: Sendable, Hashable {
    /// Enrolment is open and the student has not decided yet.
    case enrolmentOpen
    /// A mark is in and can still be refused.
    case refusable
    /// The exam is passed and recorded.
    case passed
    /// The sitting was failed.
    case failed
    /// The student is enrolled and nothing is left to decide.
    case booked
    /// Nothing is being asked: enrolment has not opened, or has closed.
    case dormant

    /// The state of one sitting.
    ///
    /// A refusable mark outranks the pass it is attached to: while the window
    /// is open, what the student can still do about the result matters more
    /// than the result.
    init(_ exam: ExamSession) {
        if let grade = exam.grade {
            self = grade.refusable ? .refusable : (grade.passed ? .passed : .failed)
            return
        }
        self = switch exam.status {
        case .open: .enrolmentOpen
        case .enrolled: .booked
        case .notYetOpen, .closed, .graded: .dormant
        }
    }

    /// On the main actor because ``Theme/brand`` is: the look's colour is read
    /// from the environment's tint, which is the app's own.
    @MainActor var tint: Color {
        switch self {
        case .enrolmentOpen: .orange
        case .refusable: .purple
        case .passed: .green
        case .failed: .red
        // Resolves through the environment's tint, so "settled" is the colour
        // the student chose for the app rather than a fixed navy.
        case .booked: Theme.brand
        case .dormant: .secondary
        }
    }

    /// The symbol that says the same thing as the colour, for the states that
    /// get one. Nothing on this page is left to hue alone.
    var symbol: String {
        switch self {
        case .enrolmentOpen: "hourglass"
        case .refusable: "arrow.uturn.backward"
        case .passed: "checkmark.seal"
        case .failed: "xmark.seal"
        case .booked: "calendar"
        case .dormant: "clock"
        }
    }

    /// What it is, in words — the other half of the pairing.
    var label: String {
        switch self {
        case .enrolmentOpen: String(localized: "Iscrizioni aperte")
        case .refusable: String(localized: "Rifiutabile")
        case .passed: String(localized: "Superato")
        case .failed: String(localized: "Non superato")
        case .booked: String(localized: "Sei iscritto")
        case .dormant: String(localized: "Niente da fare")
        }
    }
}

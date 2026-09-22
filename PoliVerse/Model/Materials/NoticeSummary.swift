import Foundation
import FoundationModels
import OSLog

/// A one-line summary of a long course announcement, written on the device.
///
/// A lecturer's notice is often four paragraphs whose point is one sentence —
/// a room has moved, a deadline has shifted, marks are up. The list can only
/// show the first line, which is usually a greeting.
///
/// Deliberately narrow, following `docs/academic-intelligence-layer.md` §22 and
/// its open question 11:
///
/// - **On the device, always.** The text is the student's course material and
///   never leaves the phone. There is no server in this app and this does not
///   add one.
/// - **Never a decision.** The summary is shown beside the notice, never in
///   place of it, and nothing in the app reads it. Detection of what changed
///   stays with the rule-based detectors (``AnnouncementDetector``,
///   ``MaterialChangeDetector``), which are deterministic and auditable; a
///   model's sentence is not evidence and is never used to tie a notice to a
///   sitting.
/// - **Absent rather than wrong.** No eligible device, no model, a refusal or
///   a timeout all produce no summary, and the notice reads as it did before.
///   Short notices are not summarised at all: a summary of two lines is two
///   lines.
@MainActor @Observable
final class NoticeSummary {
    /// How the summary stands.
    enum State: Equatable {
        /// Not asked for yet, or not worth asking for.
        case idle
        /// The model is writing.
        case writing
        /// The summary, in the notice's own language.
        case ready(String)
        /// Nothing to show, and why — kept for the diagnostics rather than the screen.
        case unavailable(String)
    }

    /// Where the summary stands.
    private(set) var state = State.idle

    /// Diagnostic log for this type, under the `summary` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "summary")

    /// Below this many characters of plain text a notice is its own summary.
    static let worthSummarising = 600
    /// The longest stretch of a notice handed to the model. A notice past this
    /// is truncated rather than refused: the point of a long notice is
    /// normally near its start.
    static let maxCharacters = 4_000

    /// What the model is told to do, once per session.
    ///
    /// It is told to work only from the notice because a model asked to be
    /// helpful about exams will otherwise supply university procedure it has
    /// read somewhere, which would be this app inventing rules.
    private static let instructions = """
        Riassumi in una sola frase l'avviso di un docente universitario a studenti.
        Scrivi nella stessa lingua dell'avviso.
        Usa solo ciò che c'è nell'avviso: non aggiungere procedure, scadenze o consigli \
        che non siano scritti lì. Se l'avviso comunica una data, un'aula o un cambiamento, \
        quella è la cosa da dire. Niente saluti, niente preamboli.
        """

    /// Whether this device can summarise at all.
    ///
    /// `false` on hardware without Apple Intelligence, with it switched off, or
    /// while the model is still downloading. The button is then not offered
    /// rather than offered and failing.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Whether a notice is long enough to be worth a summary.
    ///
    /// - Parameter text: The notice as plain text.
    /// - Returns: `true` when summarising it would say less than the notice does.
    static func isWorthSummarising(_ text: String) -> Bool {
        text.count >= worthSummarising
    }

    /// Writes the summary, replacing any previous one.
    ///
    /// - Parameter text: The notice as plain text, already stripped of markup.
    func summarise(_ text: String) async {
        guard case .available = SystemLanguageModel.default.availability else {
            state = .unavailable("model unavailable")
            log.notice("summary skipped: model unavailable")
            return
        }
        state = .writing
        let prompt = String(text.prefix(Self.maxCharacters))
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: prompt)
            let summary = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty answer is a refusal in another shape; showing an empty
            // card would be worse than showing nothing.
            guard !summary.isEmpty else {
                state = .unavailable("empty answer")
                return
            }
            state = .ready(summary)
        } catch {
            // Guardrails, a cancelled session, an exhausted context: all of
            // them mean no summary, which is a state this screen has anyway.
            state = .unavailable(error.localizedDescription)
            log.notice("summary refused: \(error.localizedDescription, privacy: .public)")
        }
    }
}

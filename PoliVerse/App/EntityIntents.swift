import AppIntents
import Foundation

/// The questions that need a subject: which course, which sitting, which room.
///
/// All three answer from the shared container, so they work from a lock screen
/// without the app in front. None of them fetches: the honest answer to "quando
/// è l'esame" is what the app last read, and each says so by naming nothing it
/// does not know.

/// "Quando è l'esame di …" — the date, room and enrolment window of one sitting.
struct ExamDateIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Quando è un esame"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Data, aula e scadenza d'iscrizione di un appello, secondo l'ultimo aggiornamento dell'app.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = false
    /// Requires an unlocked device: the answer names the student's own sitting.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    /// How the intent reads in the Shortcuts library with its parameter filled in.
    static var parameterSummary: some ParameterSummary { Summary("Quando è \(\.$exam)") }

    /// The sitting being asked about.
    @Parameter(title: "Appello")
    var exam: ExamEntity

    /// Answers with the sitting's date, room and enrolment deadline.
    ///
    /// - Returns: A spoken dialogue and the sitting itself, so a shortcut can
    ///   carry it into another step.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ExamEntity> {
        var lines: [String] = []
        if let date = exam.date {
            lines.append(String(localized: "\(exam.courseName) è il \(date.formatted(date: .long, time: .shortened))."))
        } else {
            lines.append(String(localized: "L'appello di \(exam.courseName) non ha ancora una data."))
        }
        if let room = exam.room, !room.isEmpty { lines.append(String(localized: "Aula \(room).")) }
        if let closes = exam.enrolmentCloses, closes > .now {
            lines.append(String(localized: "Iscrizioni aperte fino al \(closes.formatted(date: .abbreviated, time: .shortened))."))
        }
        return .result(value: exam, dialog: IntentDialog(stringLiteral: lines.joined(separator: " ")))
    }
}

/// "Quando ho lezione di …" — the next timetabled slot for one teaching.
struct NextLectureIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Prossima lezione di un corso"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("La prossima lezione di un corso, secondo l'orario che l'app ha già scaricato.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = false
    /// Requires an unlocked device: the answer names the student's own timetable.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    /// How the intent reads in the Shortcuts library with its parameter filled in.
    static var parameterSummary: some ParameterSummary { Summary("Prossima lezione di \(\.$course)") }

    /// The teaching being asked about.
    @Parameter(title: "Corso")
    var course: CourseEntity

    /// Answers with the next slot in the stored agenda whose title names the teaching.
    ///
    /// Matched on the title rather than on a code, because the agenda's entries
    /// carry the teaching's name and no plan code.
    ///
    /// - Returns: A spoken dialogue.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let matricola = SharedAccount.matricola else {
            return .result(dialog: "Accedi a PoliVerse per vedere il tuo orario.")
        }
        let events = OfflineStore.shared
            .load([AgendaEvent].self, as: "agenda", account: matricola)?.value ?? []
        let next = events
            .filter { $0.kind == .lecture && $0.start >= .now }
            .filter { $0.title.localizedCaseInsensitiveContains(course.name)
                || course.name.localizedCaseInsensitiveContains($0.title) }
            .min { $0.start < $1.start }
        guard let next else {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "Non trovo altre lezioni di \(course.name) nell'orario scaricato.")))
        }
        let when = next.start.formatted(date: .abbreviated, time: .shortened)
        let where_ = next.roomLabel.map { String(localized: " in \($0)") } ?? ""
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: "\(course.name) è il \(when)\(where_).")))
    }
}

/// "L'aula … è libera?" — from the same day's bookings the free-rooms widget reads.
struct RoomFreeIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Se un'aula è libera"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Se un'aula è libera adesso, e fino a quando, secondo le prenotazioni del giorno.")
    /// Brings the app forward when the intent runs.
    static let openAppWhenRun = false
    /// The room catalogue is not personal data, so no unlock is demanded.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    /// How the intent reads in the Shortcuts library with its parameter filled in.
    static var parameterSummary: some ParameterSummary { Summary("\(\.$room) è libera") }

    /// The room being asked about.
    @Parameter(title: "Aula")
    var room: RoomEntity

    /// Answers whether the room is free now, and until when.
    ///
    /// Bookings are only known for the campus the app last looked at, and only
    /// for the day it looked: any other question is answered as unknown rather
    /// than as "free", which is the answer that sends someone to a locked door.
    ///
    /// - Returns: A spoken dialogue.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let matricola = SharedAccount.matricola,
              let snapshot = OfflineStore.shared
                  .load(FreeRoomsSnapshot.self, as: FreeRoomsSnapshot.cacheName, account: matricola)?.value,
              snapshot.covers(.now),
              let booked = snapshot.rooms.first(where: { $0.id == room.id })
        else {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "Non ho le prenotazioni di oggi per \(room.name). Aprile in PoliVerse per aggiornarle.")))
        }
        let now = Date.now
        if let busy = booked.busy.first(where: { $0.start <= now && now < $0.end }) {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "\(room.name) è occupata fino alle \(busy.end.formatted(date: .omitted, time: .shortened)).")))
        }
        let nextBooking = booked.busy.filter { $0.start > now }.min { $0.start < $1.start }
        guard let nextBooking else {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "\(room.name) è libera per il resto della giornata.")))
        }
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: "\(room.name) è libera fino alle \(nextBooking.start.formatted(date: .omitted, time: .shortened)).")))
    }
}

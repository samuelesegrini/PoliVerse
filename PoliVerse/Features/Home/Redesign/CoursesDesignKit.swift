import SwiftUI

// Cinque modi diversi di disegnare Corsi, messi uno accanto all'altro.
//
// Ogni opzione è una vista *di sola presentazione*: prende una lista di
// ``CourseBrief`` e non legge nessun servizio. Così le si può guardare in
// preview a costo zero, confrontarle davvero, e adottarne una senza portarsi
// dietro il resto. Il collegamento a `CourseModel`, `AgendaModel` e al feed
// avviene una volta sola in ``CoursesRedesignPage``, quando la scelta è fatta.
//
// Quello che le cinque **non** cambiano è la casa in cui stanno: il titolo
// nella grafia di Oggi con la banda della settimana sotto, le intestazioni di
// ``LookHeading``, le carte nel materiale scelto in Personalizza, il colore
// del corso preso da ``Theme`` e quello delle novità preso dal look. Cambia il
// disegno dell'elenco, non l'app intorno — altrimenti il confronto misura
// quanto una prova somiglia a PoliVerse invece di quale elenco funziona.

/// Tutto ciò che una riga di Corsi deve sapere, in un tipo solo.
///
/// La pagina attuale ricalcola "prossima lezione" e "novità" dentro la riga,
/// il che lega il disegno ai servizi e rende impossibile provare una griglia
/// senza un `AgendaModel`. Qui il calcolo sta a monte, una volta.
struct CourseBrief: Identifiable, Hashable {
    let course: Course
    /// Prossima lezione, se c'è, già risolta.
    var nextLecture: Date?
    var nextLectureEnd: Date?
    var room: String?
    /// Prossimo appello, se c'è.
    var nextSitting: Date?
    var announcements: Int = 0
    var materials: Int = 0
    var exams: Int = 0
    /// Quota di lezioni già svolte, 0…1: quanto è avanti il corso.
    var progress: Double = 0

    var id: String { course.id }
    var unread: Int { announcements + materials + exams }
    var accent: Color { Theme.accent(for: course) }

    var isOngoing: Bool {
        guard let start = nextLecture, let end = nextLectureEnd else { return false }
        return start <= .now && end > .now
    }

    var isToday: Bool {
        guard let start = nextLecture else { return false }
        return PoliMiDate.romeCalendar.isDateInToday(start)
    }

    /// "Oggi 14:15", "Domani 10:00", "Mer 8:15" — corto perché in molte delle
    /// opzioni questa riga deve stare accanto ad altro.
    func whenText(locale: Locale) -> String? {
        guard let start = nextLecture else { return nil }
        if isOngoing { return String(localized: "In corso") }
        let time = start.formatted(.dateTime.hour().minute().locale(locale))
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(start) { return String(localized: "Oggi \(time)") }
        if calendar.isDateInTomorrow(start) { return String(localized: "Domani \(time)") }
        let day = start.formatted(.dateTime.weekday(.abbreviated).locale(locale)).capitalized
        return "\(day) \(time)"
    }

    /// "Oggi", "Domani", "Mercoledì": il giorno senza l'ora, per i disegni in
    /// cui l'ora sta già in una colonna sua.
    func dayText(locale: Locale) -> String? {
        guard let start = nextLecture else { return nil }
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(start) { return String(localized: "Oggi") }
        if calendar.isDateInTomorrow(start) { return String(localized: "Domani") }
        return start.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized
    }

    /// Docente e crediti, come li scrive il resto dell'app.
    var subtitle: String {
        var parts: [String] = []
        if !course.teacher.isEmpty, course.teacher != "—" { parts.append(course.teacher) }
        if course.cfu > 0 { parts.append("\(course.cfu) CFU") }
        return parts.joined(separator: " · ")
    }
}

extension CourseBrief {
    /// I brief veri: i corsi, con l'agenda e il feed già interrogati.
    ///
    /// L'abbinamento lezione–corso passa da ``Course/matches(_:)``, la copia
    /// buona del confronto per nome che le pagine vecchie si riscrivono a mano.
    @MainActor
    static func make(courses: [Course], agenda: AgendaModel, career: CareerModel, feed: UpdateFeed) -> [CourseBrief] {
        courses.map { course in
            let lessons = agenda.events.filter { $0.kind == .lecture && course.matches($0) }
            let next = lessons.filter { $0.end > .now }.min { $0.start < $1.start }
            let past = lessons.count { $0.end <= .now }
            let badges = CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
            return CourseBrief(
                course: course,
                nextLecture: next?.start,
                nextLectureEnd: next?.end,
                room: next?.roomAcronym ?? next?.room,
                nextSitting: career.upcoming.first { $0.isOf(courseCode: course.id, courseName: course.name) }?.date,
                announcements: badges.announcements,
                materials: badges.materials,
                exams: badges.exams,
                progress: lessons.isEmpty ? 0 : Double(past) / Double(lessons.count))
        }
    }

    /// Dati finti ma plausibili per le preview: un corso in corso adesso, uno
    /// più tardi oggi, uno domani, due senza lezione in vista. È la situazione
    /// in cui ogni opzione va giudicata — non sei corsi tutti uguali.
    static var samples: [CourseBrief] {
        let now = Date.now
        let samples = Course.samples
        return [
            CourseBrief(course: samples[0], nextLecture: now.addingTimeInterval(-900),
                        nextLectureEnd: now.addingTimeInterval(2_700), room: "B.2.1",
                        announcements: 2, materials: 1, progress: 0.62),
            CourseBrief(course: samples[1], nextLecture: now.addingTimeInterval(3 * 3_600),
                        nextLectureEnd: now.addingTimeInterval(5 * 3_600), room: "3.0.2",
                        materials: 3, progress: 0.48),
            CourseBrief(course: samples[2], nextLecture: now.addingTimeInterval(26 * 3_600),
                        nextLectureEnd: now.addingTimeInterval(28 * 3_600), room: "L.26.02",
                        progress: 0.71),
            CourseBrief(course: samples[3], nextLecture: now.addingTimeInterval(3 * 86_400),
                        nextLectureEnd: now.addingTimeInterval(3 * 86_400 + 7_200), room: "7.0.1",
                        nextSitting: now.addingTimeInterval(21 * 86_400),
                        announcements: 1, exams: 2, progress: 0.30),
            CourseBrief(course: samples[4], progress: 0.95),
            CourseBrief(course: samples[5], nextSitting: now.addingTimeInterval(12 * 86_400),
                        exams: 1, progress: 1.0),
        ]
    }
}

// MARK: - Pezzi condivisi fra le opzioni

/// Il contatore delle novità accanto a un corso, nel colore del look.
///
/// Uno solo, non tre: avvisi, materiali e appelli distinti in tre pastiglie
/// accanto al titolo si leggono come rumore e nessuno impara cosa distinguono
/// — la pagina del corso li separa, dove c'è lo spazio per dirlo a parole.
/// Il colore è quello che lo studente ha scelto in Personalizza, come già fa
/// la riga di ``CoursesPage``, non un rosso di sistema.
struct CourseBadge: View {
    let count: Int
    /// Su una superficie già colorata — la carta della lezione in corso — il
    /// contatore non può essere del colore del look: si perderebbe dentro.
    var onColour = false

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if count > 0 {
            let palette = style.palette(scheme)
            Text(count, format: .number)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(onColour ? Theme.onAccent : palette.onAccent)
                .padding(.horizontal, 7)
                .frame(minWidth: 22, minHeight: 22)
                .background(onColour ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(palette.accent), in: .capsule)
                .accessibilityLabel(Text("\(count) novità"))
        }
    }
}

/// La carta piena del colore di un corso, come Oggi disegna la lezione in
/// corso: angoli a 22, la lucentezza del look, l'ombra del suo stesso colore.
///
/// Sta qui perché tre delle cinque opzioni ne hanno una, e se ognuna se la
/// disegnasse da sé il confronto misurerebbe l'ombra invece dell'elenco.
struct CourseAccentCard<Content: View>: View {
    let colour: Color
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(colour)
                    .visualEffect { content, proxy in
                        content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.5)))
                    }
            }
            .shadow(color: colour.opacity(0.3), radius: 8, y: 4)
            .contentShape(shape)
    }
}

/// Un anello di avanzamento attorno a un contenuto: quanto del corso è fatto.
struct ProgressRing<Content: View>: View {
    let value: Double
    let tint: Color
    var lineWidth: CGFloat = 3
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(lineWidth + 2)
            .background {
                Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            }
            .overlay {
                Circle()
                    .trim(from: 0, to: max(0.02, min(value, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Una riga dentro una carta, come le disegna ``CardRow``: stessa
    /// spaziatura, stesso filo sotto, stesso rientro del filo.
    func courseRowPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 11)
    }
}

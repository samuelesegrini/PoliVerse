import SwiftUI

// Cinque modi diversi di disegnare Corsi, messi uno accanto all'altro.
//
// Ogni opzione è una vista *di sola presentazione*: prende una lista di
// ``CourseBrief`` e non legge nessun servizio. Così le si può guardare in
// preview a costo zero, confrontarle davvero, e adottarne una senza portarsi
// dietro il resto. Il collegamento a `CourseModel`, `AgendaModel` e al feed
// avviene una volta sola in ``CoursesRedesignPage``, quando la scelta è fatta.

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

    var subtitle: String {
        var parts: [String] = []
        if !course.teacher.isEmpty, course.teacher != "—" { parts.append(course.teacher) }
        if course.cfu > 0 { parts.append("\(course.cfu) CFU") }
        return parts.joined(separator: " · ")
    }
}

extension CourseBrief {
    /// I brief veri: i corsi, con l'agenda e il feed già interrogati.
    @MainActor
    static func make(courses: [Course], agenda: AgendaModel, career: CareerModel, feed: UpdateFeed) -> [CourseBrief] {
        courses.map { course in
            let target = course.name.lowercased()
            let matches: (AgendaEvent) -> Bool = { event in
                let title = event.title.lowercased()
                return title.contains(target) || target.contains(title)
            }
            let lessons = agenda.events.filter { $0.kind == .lecture && matches($0) }
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

    /// Solo le lezioni di oggi ancora da finire, nell'ordine in cui accadono.
    static func today(in list: [CourseBrief]) -> [CourseBrief] {
        list.filter { $0.isToday && ($0.nextLectureEnd ?? .distantPast) > .now }
            .sorted { ($0.nextLecture ?? .distantFuture) < ($1.nextLecture ?? .distantFuture) }
    }
}

// MARK: - Pezzi condivisi fra le opzioni

/// Il pallino delle novità: un numero solo, perché tre badge diversi accanto
/// al titolo si leggono come rumore e nessuno impara cosa distinguono.
struct UnreadDot: View {
    let count: Int
    var tint: Color = .red

    var body: some View {
        if count > 0 {
            Text(count, format: .number)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(tint, in: .capsule)
                .accessibilityLabel(Text("\(count) novità"))
        }
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

/// Le iniziali del corso sul suo colore, in quadrato o in tondo.
struct CourseGlyph: View {
    let course: Course
    var size: CGFloat = 40
    var circular = false
    var filled = true

    var body: some View {
        let accent = Theme.accent(for: course)
        Text(course.monogram)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Theme.onAccent : accent)
            .frame(width: size, height: size)
            .background {
                if circular {
                    Circle().fill(filled ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.15)))
                } else {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(filled ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.15)))
                }
            }
            .accessibilityHidden(true)
    }
}

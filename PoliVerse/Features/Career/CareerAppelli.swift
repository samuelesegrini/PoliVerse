import SwiftUI

/// The sittings, grouped by what the student has to decide about them.
///
/// Not by the date of the exam, which is the wrong clock: an exam in June
/// that you must enrol for by Friday is more urgent than one in January you
/// are already enrolled in. What costs a session is the *decision* expiring,
/// so that is what the order and the rows lead with.
nonisolated struct ExamAgenda {
    /// A group of sittings under one heading.
    struct Section: Identifiable {
        /// The group's identity, which is its heading.
        let id: String
        /// The heading.
        let title: String
        /// Said once under the group rather than on each of its rows.
        let footnote: String?
        /// The sittings in the group, in the order they need attention.
        let exams: [ExamSession]
    }

    /// The sittings split by what is being asked of the student, in the order
    /// they need attention: what is still open to decide, what is booked,
    /// what has not opened yet, and what can no longer be joined.
    static func sections(from sessions: [ExamSession], now: Date = .now,
                         calendar: Calendar = PoliMiDate.romeCalendar) -> [Section] {
        let today = calendar.startOfDay(for: now)
        let live = sessions.filter { $0.grade == nil && ($0.date ?? .distantPast) >= today }

        func group(_ id: String, _ title: String, _ footnote: String? = nil,
                   _ filter: (ExamSession) -> Bool,
                   by key: (ExamSession) -> Date?) -> Section? {
            let exams = live.filter(filter).sorted {
                (key($0) ?? .distantFuture) < (key($1) ?? .distantFuture)
            }
            return exams.isEmpty ? nil : Section(id: id, title: title, footnote: footnote, exams: exams)
        }

        return [
            group("open", String(localized: "Da decidere"), nil,
                  { $0.status == .open }, by: \.enrolmentCloses),
            group("enrolled", String(localized: "Sei iscritto"), nil,
                  { $0.status == .enrolled }, by: \.date),
            group("soon", String(localized: "Non ancora aperti"),
                  String(localized: "PoliVerse ti avvisa l'ultimo giorno utile per iscriverti, se i promemoria sugli appelli sono attivi."),
                  { $0.status == .notYetOpen }, by: \.enrolmentOpens),
            group("closed", String(localized: "Iscrizioni chiuse"), nil,
                  { $0.status == .closed }, by: \.date),
        ].compactMap { $0 }
    }
}

/// One sitting, leading with whatever the student has to act on.
///
/// An open window leads with when it shuts, in words and in orange; a booked
/// sitting leads with its date, because there is nothing left to decide and
/// the question becomes "when". Same row, two different first lines, decided
/// by what the student can still do about it.
struct ExamRow: View {
    /// The sitting this row is about.
    let exam: ExamSession

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// What the sitting is asking of the student, which picks the row's colour and words.
    private var state: CareerState { CareerState(exam) }

    /// The view's content.
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if exam.status == .enrolled, let date = exam.date {
                dateGutter(date)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let urgency {
                    Label(urgency, systemImage: state.symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(state.tint)
                }
                Text(exam.courseName)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard()
        .accessibilityElement(children: .combine)
    }

    /// The day and month at the row's leading edge, for a sitting already booked.
    ///
    /// - Parameter date: The sitting's date.
    /// - Returns: The gutter.
    private func dateGutter(_ date: Date) -> some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.day().locale(locale)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(date.formatted(.dateTime.month(.abbreviated).locale(locale)).uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 44)
        .accessibilityElement(children: .combine)
    }

    /// The deadline in the words a student uses, for the rows that have one.
    private var urgency: String? {
        guard exam.status == .open, let closes = exam.enrolmentCloses,
              let days = PoliMiDate.romeCalendar.dateComponents(
                [.day], from: PoliMiDate.romeCalendar.startOfDay(for: .now),
                to: PoliMiDate.romeCalendar.startOfDay(for: closes)).day
        else { return nil }
        return switch days {
        case ...0: String(localized: "Le iscrizioni chiudono oggi")
        case 1: String(localized: "Le iscrizioni chiudono domani")
        default: String(localized: "Le iscrizioni chiudono fra \(days) giorni")
        }
    }

    /// The row's second line, which says what is known about the sitting's dates.
    private var detail: String {
        let day = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        switch exam.status {
        case .notYetOpen:
            let opens = exam.enrolmentOpens.map {
                String(localized: "Iscrizioni dal \($0.formatted(day))")
            }
            let sitting = exam.date.map { String(localized: "appello del \($0.formatted(day))") }
            return [opens, sitting].compactMap { $0 }.joined(separator: " · ")
        case .closed:
            return exam.date.map { String(localized: "Appello del \($0.formatted(day))") } ?? exam.status.label
        case .enrolled:
            let time = exam.date.map { $0.formatted(.dateTime.hour().minute().locale(locale)) }
            let room = exam.room
            let count = exam.enrolledCount.flatMap { $0 > 0 ? String(localized: "\($0) iscritti") : nil }
            return [time, room, count].compactMap { $0 }.joined(separator: " · ")
        case .open, .graded:
            let kind = exam.kind?.sentenceCased
            let sitting = exam.date.map { $0.formatted(day) }
            let count = exam.enrolledCount.flatMap { $0 > 0 ? String(localized: "\($0) iscritti") : nil }
            return [kind, sitting, count].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

// MARK: - Previews

#Preview("Appelli") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ExamAgenda.sections(from: ExamSession.samples())) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(section.exams) { ExamRow(exam: $0) }
                }
            }
        }
        .padding(16)
    }
    .previewEnvironment()
}

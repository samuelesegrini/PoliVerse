import SwiftUI

/// Something on the student's career that stops being possible on a date.
///
/// The libretto, the average and the list of sittings are all *states* — they
/// are true today and will still be true next week — while the two things
/// that actually cost a student something are deadlines: an enrolment window
/// that closes, and a mark that can only be refused until it cannot. Missing
/// the first costs a session, which is months. These are drawn apart from the
/// states, at the top of the page, rather than left as a colour on a row.
nonisolated struct CareerDeadline: Identifiable, Sendable {
    /// Which kind of deadline this is.
    enum Kind: Sendable {
        /// Enrolment is open and the student is not enrolled.
        case enrolmentClosing
        /// A mark is published and can still be refused.
        case refusableGrade
        /// Enrolled, and the sitting is imminent.
        case sitting
    }

    /// Which kind of deadline this is.
    let kind: Kind
    /// The sitting it belongs to.
    let exam: ExamSession

    /// The colour and the words this deadline is shown in.
    var state: CareerState {
        switch kind {
        case .enrolmentClosing: .enrolmentOpen
        case .refusableGrade: .refusable
        case .sitting: .booked
        }
    }
    /// When it stops being possible. Absent for a refusable mark: the
    /// Politecnico publishes no refusal deadline through these services, and
    /// inventing one would be worse than not having it.
    let at: Date?

    /// The deadline's identity, which pairs the sitting with the kind.
    var id: String { "\(exam.id)-\(kind)" }

    /// Days from `now`, for the sort and for the wording.
    func days(from now: Date, calendar: Calendar = PoliMiDate.romeCalendar) -> Int? {
        guard let at else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: at)).day
    }

    /// What is expiring, soonest first; undated last.
    ///
    /// Sorted by the deadline rather than by kind, because which of them
    /// matters most genuinely depends on the dates: an enrolment closing
    /// tonight outranks an exam the day after tomorrow, and the reverse is
    /// equally true a week earlier.
    static func all(in sessions: [ExamSession], now: Date = .now,
                    calendar: Calendar = PoliMiDate.romeCalendar) -> [CareerDeadline] {
        var found: [CareerDeadline] = []
        for exam in sessions {
            if let grade = exam.grade {
                if grade.refusable {
                    found.append(CareerDeadline(kind: .refusableGrade, exam: exam, at: nil))
                }
                continue
            }
            switch exam.status {
            case .open:
                // An open window matters from the day it could be missed, not
                // from the day it opens: a month of "iscrizioni aperte" at the
                // top of the page is a banner people stop reading.
                if let closes = exam.enrolmentCloses, closes > now,
                   let days = calendar.dateComponents([.day], from: now, to: closes).day, days <= 14 {
                    found.append(CareerDeadline(kind: .enrolmentClosing, exam: exam, at: closes))
                }
            case .enrolled:
                if let date = exam.date, date > now,
                   date.timeIntervalSince(now) <= 48 * 3600 {
                    found.append(CareerDeadline(kind: .sitting, exam: exam, at: date))
                }
            case .notYetOpen, .closed, .graded:
                continue
            }
        }
        return found.sorted { left, right in
            switch (left.at, right.at) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return left.exam.id < right.exam.id
            }
        }
    }
}

/// Adesso: the deadlines, at the top of Carriera, or nothing at all.
///
/// Deliberately has no empty state. A card reading "niente in scadenza" would
/// be on screen nearly every day of the year, and a thing that is nearly
/// always there stops being read on the day it says something. When nothing
/// expires the page simply begins with the average.
struct CareerNowCard: View {
    /// The deadlines to show, most urgent first.
    let deadlines: [CareerDeadline]
    /// Opens a sitting's own screen.
    let open: (ExamSession) -> Void

    /// The look in use, which supplies the card's material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        if let first = deadlines.first {
            let second = deadlines.dropFirst().first
            VStack(alignment: .leading, spacing: 14) {
                // The heading takes the colour of what it is heading, so
                // the card reads as one thing rather than an orange label
                // over a purple one.
                Text("ADESSO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(first.state.tint)
                    .accessibilityHidden(true)

                headline(first)

                if let second {
                    Divider()
                    compact(second)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The same glass the sitting's own page is made of: Adesso is the
            // way into it, and reading as the same material says so.
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
        }
    }

    // MARK: - The first one, in full

    /// The first deadline in full: what it is, how long is left, what to do about it, and the way through.
    ///
    /// - Parameter deadline: The deadline to show.
    /// - Returns: The headline.
    @ViewBuilder
    private func headline(_ deadline: CareerDeadline) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(deadline))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let urgency = urgency(deadline) {
                    Label(urgency, systemImage: deadline.state.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(deadline.state.tint)
                }
                Text(detail(deadline))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Combined here and not around the whole block: flattening the
            // button into the text would cost Carriera's primary action its
            // button trait and its activation point.
            .accessibilityElement(children: .combine)

            // Not "Iscriviti": enrolment is a write against the university's
            // own system and this app deliberately does not make it
            // (``ExamDetailView`` says so). The button opens the sitting,
            // where the window and the route to Servizi Online are.
            Button { open(deadline.exam) } label: {
                Text(action(deadline))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - The next one, on one line

    /// A further deadline on one line under the first.
    ///
    /// - Parameter deadline: The deadline to show.
    /// - Returns: The row.
    private func compact(_ deadline: CareerDeadline) -> some View {
        Button { open(deadline.exam) } label: {
            HStack(spacing: 12) {
                marker(deadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deadline.exam.courseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(urgency(deadline) ?? detail(deadline))
                        .font(.footnote)
                        .foregroundStyle(deadline.state.tint)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// The tile at a row's leading edge: the mark itself for a refusable grade, the state's symbol otherwise.
    ///
    /// - Parameter deadline: The deadline.
    /// - Returns: The tile.
    @ViewBuilder
    private func marker(_ deadline: CareerDeadline) -> some View {
        let tint = deadline.state.tint
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.15))
            if case .refusableGrade = deadline.kind, let grade = deadline.exam.grade {
                Text(grade.display)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .foregroundStyle(tint)
            } else {
                Image(systemName: deadline.state.symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 42, height: 42)
    }

    // MARK: - Words

    /// What the deadline is, in the words its kind calls for.
    ///
    /// - Parameter deadline: The deadline.
    /// - Returns: The title.
    private func title(_ deadline: CareerDeadline) -> String {
        switch deadline.kind {
        case .enrolmentClosing:
            String(localized: "Iscrizioni a \(deadline.exam.courseName)")
        case .refusableGrade:
            String(localized: "\(deadline.exam.grade?.display ?? "—") in \(deadline.exam.courseName)")
        case .sitting:
            deadline.exam.courseName
        }
    }

    /// The deadline in the words a student uses. Nil for a refusable mark,
    /// which has no published deadline to put in them.
    private func urgency(_ deadline: CareerDeadline) -> String? {
        let day = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(locale)
        switch deadline.kind {
        case .enrolmentClosing:
            guard let at = deadline.at, let days = deadline.days(from: .now) else { return nil }
            let when = at.formatted(day)
            return switch days {
            case ...0: String(localized: "Chiudono oggi · \(when)")
            case 1: String(localized: "Chiudono domani · \(when)")
            default: String(localized: "Chiudono fra \(days) giorni · \(when)")
            }
        case .sitting:
            guard let at = deadline.at, let days = deadline.days(from: .now) else { return nil }
            let time = at.formatted(.dateTime.hour().minute().locale(locale))
            // Counted in days, not in hours: 48 hours before a Wednesday
            // nine o'clock is Monday evening, and calling that "domani" is
            // wrong on the card the student trusts most.
            return switch days {
            case ...0: String(localized: "Oggi alle \(time)")
            case 1: String(localized: "Domani alle \(time)")
            default: String(localized: "Fra \(days) giorni alle \(time)")
            }
        case .refusableGrade:
            return String(localized: "Puoi ancora rifiutarlo")
        }
    }

    /// The second line: the sitting's date and kind, its room, or where the action is actually taken.
    ///
    /// - Parameter deadline: The deadline.
    /// - Returns: The line.
    private func detail(_ deadline: CareerDeadline) -> String {
        let day = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        switch deadline.kind {
        case .enrolmentClosing:
            guard let date = deadline.exam.date else {
                return String(localized: "Le iscrizioni si gestiscono dai Servizi Online.")
            }
            let kind = deadline.exam.kind.map { "\($0.sentenceCased) · " } ?? ""
            return kind + String(localized: "appello del \(date.formatted(day))")
        case .refusableGrade:
            return String(localized: "Il rifiuto si fa dai Servizi Online, finché la finestra resta aperta.")
        case .sitting:
            let room = deadline.exam.room
            let enrolled = deadline.exam.enrolledCount.map { String(localized: "\($0) iscritti") }
            return [room, enrolled].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// What the button under the headline says.
    ///
    /// - Parameter deadline: The deadline.
    /// - Returns: The wording.
    private func action(_ deadline: CareerDeadline) -> String {
        switch deadline.kind {
        case .enrolmentClosing: String(localized: "Vedi l'appello")
        case .refusableGrade: String(localized: "Vedi l'esito")
        case .sitting: String(localized: "Vedi l'appello")
        }
    }
}

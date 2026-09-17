import SwiftUI

/// Everything known about one exam sitting: the sitting itself, the
/// enrolment window, the mark and what it does to the mean, the course's
/// other sittings and earlier attempts, how the exam works, and its history.
struct ExamDetailView: View {
    @State private var exam: ExamSession

    init(exam: ExamSession) {
        _exam = State(initialValue: exam)
    }

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(CareerModel.self) private var career
    @Environment(CourseModel.self) private var courses
    /// Captured when the button is tapped, so the sheet keeps its event even
    /// if the sitting's start passes while it is open.
    @State private var calendarDraft: ExamCalendarEvent?

    /// Only for a sitting still ahead: past ones have no use in a calendar.
    private var calendarEvent: ExamCalendarEvent? {
        guard (exam.date ?? .distantPast) > .now else { return nil }
        return ExamCalendarEvent(sitting: exam)
    }

    private var context: ExamContext {
        ExamContext(exam: exam, sittings: career.sessions, libretto: career.libretto, now: .now)
    }

    /// The student's course page, when WeBeep or the plan lists it.
    private var course: Course? {
        courses.courses.first { exam.isOf(courseCode: $0.code ?? $0.id, courseName: $0.name) }
    }

    private var accent: Color { ExamDetailView.accent(for: exam.status) }

    static func accent(for status: ExamStatus) -> Color {
        switch status {
        case .graded(let grade): grade.passed ? .green : .red
        case .enrolled: Theme.brand
        case .open: .orange
        case .notYetOpen, .closed: .secondary
        }
    }

    var body: some View {
        let context = context
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero(context)
                    quickActions

                    if let grade = exam.grade {
                        resultSection(grade, context: context)
                    } else {
                        enrolmentSection
                    }

                    detailsSection(context)

                    ExamFormatSection(exam: exam)

                    if !context.previousAttempts.isEmpty {
                        sittingsSection("Tentativi precedenti", context.previousAttempts)
                    }
                    if !context.otherUpcoming.isEmpty {
                        sittingsSection(exam.grade == nil ? "Altri appelli" : "Prossimi appelli",
                                        context.otherUpcoming)
                    }

                    ExamTimelineSection(exam: exam)
                }
                .padding()
                .padding(.bottom, 20)
                .animation(.snappy, value: exam.id)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(item: $calendarDraft) { AddToCalendarSheet(event: $0).ignoresSafeArea() }
            .navigationTitle(exam.kind?.nonEmpty ?? String(localized: "Appello"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero

    private func hero(_ context: ExamContext) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(exam.courseName)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .fixedSize(horizontal: false, vertical: true)

                if let teacher = exam.teacher {
                    Text(teacher)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    chip(exam.grade.map { $0.passed ? String(localized: "Superato") : String(localized: "Non superato") }
                         ?? exam.status.label, tint: accent)
                    if let cfu = context.librettoEntry?.cfu, cfu > 0 {
                        chip("\(cfu) CFU", tint: .secondary)
                    }
                }

                if let countdown {
                    Text(countdown)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let grade = exam.grade {
                GradeRing(grade: grade, tint: accent)
            } else if let date = exam.date {
                dateBadge(date)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [accent.opacity(0.3), accent.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 130))
                        .frame(width: 240, height: 240)
                        .offset(x: 80, y: -100)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
        }
    }

    /// "Tra 12 giorni", "Domani", "Oggi alle 9:00" — for a sitting ahead.
    private var countdown: String? {
        guard exam.grade == nil, let date = exam.date, date > .now else { return nil }
        let calendar = PoliMiDate.romeCalendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        switch days {
        case 0: return String(localized: "Oggi alle \(time)")
        case 1: return String(localized: "Domani alle \(time)")
        default: return String(localized: "Tra \(days) giorni")
        }
    }

    private func dateBadge(_ date: Date) -> some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated).locale(locale)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(accent)
            Text(date.formatted(.dateTime.day().locale(locale)))
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .padding(.top, 4)
            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
        }
        .frame(width: 68)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    @ViewBuilder
    private var quickActions: some View {
        let hasCalendar = calendarEvent != nil
        if hasCalendar || course != nil {
            HStack(spacing: 8) {
                if hasCalendar {
                    Button { calendarDraft = calendarEvent } label: {
                        actionTile("Calendario", "calendar.badge.plus")
                    }
                }
                if let course {
                    NavigationLink { CourseDetailView(course: course) } label: {
                        actionTile("Corso", "books.vertical.fill")
                    }
                    NavigationLink { CourseMaterialsView(course: course) } label: {
                        actionTile("Materiali", "folder.fill")
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func actionTile(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent)
            Text(title).font(.caption.weight(.medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, 4)
        .cardBackground()
        .contentShape(.rect)
    }

    // MARK: - Result

    private func resultSection(_ grade: ExamGrade, context: ExamContext) -> some View {
        section("Esito") {
            VStack(alignment: .leading, spacing: 12) {
                if let impact = context.meanImpact {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media dopo la registrazione")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(impact.before, format: .number.precision(.fractionLength(2)))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(impact.after, format: .number.precision(.fractionLength(2)))
                                    .font(.title3.weight(.bold))
                                    .fontDesign(.rounded)
                            }
                            .monospacedDigit()
                        }
                        Spacer()
                        Text(impact.delta, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((impact.delta >= 0 ? Color.green : .orange).opacity(0.15), in: .capsule)
                            .foregroundStyle(impact.delta >= 0 ? .green : .orange)
                    }
                    Text("Stima sui voti del libretto pesati per CFU (\(impact.cfu) CFU per questo esame).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let entry = context.librettoEntry, entry.isPassed {
                    Label("Registrato nel libretto", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }

                if grade.refusable {
                    // Worth stating plainly: the window to refuse a mark is
                    // short and easy to miss.
                    Label("Puoi ancora rifiutare questo voto dai Servizi Online.",
                          systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if exam.hasCorrections {
                    Label("Elaborato corretto consultabile sui Servizi Online.",
                          systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
                if !grade.passed {
                    Label("Il voto non entra nella media: puoi ripresentarti a un prossimo appello.",
                          systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    // MARK: - Enrolment

    private var enrolmentSection: some View {
        section("Iscrizione") {
            VStack(alignment: .leading, spacing: 12) {
                if let opens = exam.enrolmentOpens, let closes = exam.enrolmentCloses, closes > opens {
                    EnrolmentWindowBar(opens: opens, closes: closes, examDate: exam.date, tint: accent)
                }

                if let deadline = deadlineText {
                    Label(deadline, systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(exam.status == .open ? .orange : .secondary)
                }

                if let count = exam.enrolledCount, count > 0 {
                    Label("\(count) iscritti", systemImage: "person.3.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Enrolment is a write against the real university system.
                // Doing it from here untested could sign someone up for an
                // exam by accident, so the app points at the official
                // services instead of guessing at the API.
                Text("Le iscrizioni agli appelli si gestiscono dai Servizi Online del Politecnico.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private var deadlineText: String? {
        let format = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        switch exam.status {
        case .open:
            guard let closes = exam.enrolmentCloses else { return nil }
            return String(localized: "Iscrizioni aperte fino al \(closes.formatted(format))")
        case .notYetOpen:
            guard let opens = exam.enrolmentOpens else { return nil }
            return String(localized: "Le iscrizioni aprono il \(opens.formatted(format))")
        case .enrolled:
            return String(localized: "Sei iscritto a questo appello")
        case .closed:
            return String(localized: "Iscrizioni chiuse")
        case .graded:
            return nil
        }
    }

    // MARK: - Details

    private func detailsSection(_ context: ExamContext) -> some View {
        section("Dettagli") {
            VStack(spacing: 0) {
                let rows = detailRows(context)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                    detailRow(item.label, item.value, icon: item.icon)
                    if index < rows.count - 1 { Divider().padding(.leading, 48) }
                }
            }
            .cardBackground()
        }
    }

    private func detailRows(_ context: ExamContext) -> [(label: String, value: String, icon: String)] {
        var rows: [(String, String, String)] = []
        if let date = exam.date {
            rows.append((String(localized: "Data"),
                         date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)).capitalized,
                         "calendar"))
            rows.append((String(localized: "Ora"), date.formatted(.dateTime.hour().minute().locale(locale)), "clock"))
        }
        if let room = exam.room { rows.append((String(localized: "Aula"), room, "mappin.and.ellipse")) }
        if let kind = exam.kind?.nonEmpty { rows.append((String(localized: "Tipo"), kind, "doc.text")) }
        if let teacher = exam.teacher { rows.append((String(localized: "Docente"), teacher, "person")) }
        if let year = context.librettoEntry?.year { rows.append((String(localized: "Anno"), year, "graduationcap")) }
        rows.append((String(localized: "Codice"), exam.courseCode, "number"))
        return rows
    }

    private func detailRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // MARK: - Other sittings

    private func sittingsSection(_ title: LocalizedStringKey, _ sittings: [ExamSession]) -> some View {
        section(title) {
            VStack(spacing: 0) {
                ForEach(Array(sittings.enumerated()), id: \.element.id) { index, sitting in
                    Button { exam = sitting } label: { sittingRow(sitting) }
                        .buttonStyle(.plain)
                    if index < sittings.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            .cardBackground()
        }
    }

    private func sittingRow(_ sitting: ExamSession) -> some View {
        let tint = ExamDetailView.accent(for: sitting.status)
        return HStack(spacing: 12) {
            Group {
                if let grade = sitting.grade {
                    Text(grade.display)
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "calendar").foregroundStyle(tint)
                }
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(sitting.date?.formatted(.dateTime.day().month(.wide).year().locale(locale))
                     ?? String(localized: "Data da definire"))
                    .font(.subheadline.weight(.medium))
                Text([sitting.kind?.nonEmpty, sitting.grade == nil ? sitting.status.label : nil, sitting.room]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(.rect)
    }

    // MARK: - Building blocks

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }
}

// MARK: - Components

/// The mark on a ring filled to its share of 30.
private struct GradeRing: View {
    let grade: ExamGrade
    let tint: Color

    private var fraction: Double {
        guard let value = grade.value else { return grade.passed ? 1 : 0 }
        return min(Double(value) / 30, 1)
    }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(grade.display)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if grade.value != nil {
                    Text("/30").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Voto \(grade.display)"))
    }
}

/// Opening, closing and the sitting on one line, with today marked.
private struct EnrolmentWindowBar: View {
    let opens: Date
    let closes: Date
    let examDate: Date?
    let tint: Color

    @Environment(\.locale) private var locale

    private var progress: Double {
        min(max(Date.now.timeIntervalSince(opens) / closes.timeIntervalSince(opens), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(tint).frame(width: max(proxy.size.width * progress, 6))
                }
            }
            .frame(height: 8)

            HStack {
                label("Apertura", opens, alignment: .leading)
                Spacer()
                label("Chiusura", closes, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ title: LocalizedStringKey, _ date: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Previews

#Preview("Appello") {
    ExamDetailView(exam: ExamSession.samples()[0]).previewEnvironment()
}

#Preview("Esito") {
    ExamDetailView(exam: ExamSession.samples().first { $0.grade != nil }!).previewEnvironment()
}

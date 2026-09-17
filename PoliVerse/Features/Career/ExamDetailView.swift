import SwiftUI

/// Everything known about one exam sitting, as layers of glass over the look's
/// page.
///
/// A quiet header says which course and when. Under it one glass panel holds
/// the sitting: its type and where it stands, the grade once there is one, the
/// facts side by side, and the enrolment window while it matters. Actions sit
/// in a row of glass buttons that merge as one, the other dates are glass
/// chips to flip through, and how the exam works and its history follow.
struct ExamDetailView: View {
    @State private var exam: ExamSession

    init(exam: ExamSession) {
        _exam = State(initialValue: exam)
    }

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(CareerService.self) private var career
    @Environment(CourseService.self) private var courses
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    /// Scaled, so the tile grows with the reader's text like the settings pictures.
    @ScaledMetric(relativeTo: .largeTitle) private var tileSide: CGFloat = 104
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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sittingPanel(context)
                    actions

                    if let impact = context.meanImpact {
                        meanPanel(impact)
                    }

                    let others = context.otherUpcoming + context.previousAttempts
                    if !others.isEmpty {
                        otherDates(others)
                    }

                    VStack(alignment: .leading, spacing: 26) {
                        ExamFormatSection(exam: exam)
                        ExamTimelineSection(exam: exam)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: exam.id)
            }
            .courseScreen()
            .sheet(item: $calendarDraft) { AddToCalendarSheet(event: $0).ignoresSafeArea() }
            .navigationTitle(exam.courseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The header names the course: the bar only closes the sheet.
                ToolbarItem(placement: .principal) { Text(verbatim: "") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    /// The subject as a glass tile in the middle, then which course and when,
    /// with how far off it is in a glass pill.
    private var header: some View {
        let ramp = course.map { CourseRamp(course: $0, style: style, scheme: scheme) }
            ?? CourseRamp(name: exam.courseName, style: style, scheme: scheme)
        return VStack(spacing: 10) {
            GlassTile(symbol: SubjectSymbol.symbol(for: exam.courseName), colour: ramp.main, side: tileSide,
                      surface: .glass, mode: ramp.mode)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(exam.courseName)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let date = exam.date {
                Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized) · \(date.formatted(.dateTime.hour().minute().locale(locale)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let countdown {
                Text(countdown)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    /// "Oggi", "Domani", "Tra 12 giorni" — for a sitting ahead.
    private var countdown: String? {
        guard exam.grade == nil, let date = exam.date, date > .now else { return nil }
        let calendar = PoliMiDate.romeCalendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "Oggi")
        case 1: return String(localized: "Domani")
        default: return String(localized: "Tra \(days) giorni")
        }
    }

    // MARK: - The sitting

    /// The type and where it stands, the grade, the facts, and the enrolment
    /// window while it is still to come.
    private func sittingPanel(_ context: ExamContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exam.kind?.nonEmpty ?? String(localized: "Appello"))
                        .font(.title2.weight(.bold))
                    Label {
                        Text(statusSentence(context))
                    } icon: {
                        Circle().fill(ExamDetailView.accent(for: exam.status)).frame(width: 8, height: 8)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let grade = exam.grade {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(grade.display)
                            .font(style.dateFont.font(size: 40, weight: style.dateWeight))
                            .lineLimit(1)
                        if grade.value != nil {
                            Text("su 30").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Voto \(grade.display)"))
                }
            }

            let facts = facts(context)
            if !facts.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .topLeading)],
                          alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fact.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.headline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if exam.grade == nil, let opens = exam.enrolmentOpens, let closes = exam.enrolmentCloses, closes > opens,
               exam.status == .open || exam.status == .notYetOpen {
                EnrolmentWindowBar(opens: opens, closes: closes, tint: ExamDetailView.accent(for: exam.status))
            }

            if let grade = exam.grade {
                if grade.refusable {
                    Label("Puoi ancora rifiutare questo voto dai Servizi Online.", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if exam.hasCorrections {
                    Label("Elaborato corretto consultabile sui Servizi Online.", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
            } else {
                // Enrolment is a write against the real university system:
                // the app points at the official services instead.
                Text("Le iscrizioni si gestiscono dai Servizi Online del Politecnico.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private func statusSentence(_ context: ExamContext) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        if let grade = exam.grade {
            guard grade.passed else { return String(localized: "Non superato: non entra nella media") }
            if context.librettoEntry?.isPassed == true { return String(localized: "Superato e registrato nel libretto") }
            return String(localized: "Superato, da registrare")
        }
        switch exam.status {
        case .open:
            return exam.enrolmentCloses.map { String(localized: "Iscrizioni aperte fino al \($0.formatted(format))") }
                ?? String(localized: "Iscrizioni aperte")
        case .notYetOpen:
            return exam.enrolmentOpens.map { String(localized: "Le iscrizioni aprono il \($0.formatted(format))") }
                ?? String(localized: "Iscrizioni non ancora aperte")
        case .enrolled: return String(localized: "Sei iscritto")
        case .closed: return String(localized: "Iscrizioni chiuse")
        case .graded: return ""
        }
    }

    private func facts(_ context: ExamContext) -> [(label: String, value: String)] {
        [
            exam.date.map { (String(localized: "Ora"), $0.formatted(.dateTime.hour().minute().locale(locale))) },
            exam.room.map { (String(localized: "Aula"), $0) },
            exam.enrolledCount.flatMap { $0 > 0 ? (String(localized: "Iscritti"), "\($0)") : nil },
            context.librettoEntry?.cfu.flatMap { $0 > 0 ? (String(localized: "CFU"), "\($0)") : nil },
            exam.teacher.map { (String(localized: "Docente"), $0) },
            (String(localized: "Codice"), exam.courseCode),
        ].compactMap { $0 }
    }

    // MARK: - Actions

    /// The calendar for a sitting ahead, and the course with its materials,
    /// as glass buttons that read as one bar.
    @ViewBuilder
    private var actions: some View {
        if calendarEvent != nil || course != nil {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if let event = calendarEvent {
                        Button { calendarDraft = event } label: {
                            Label("Calendario", systemImage: "calendar.badge.plus")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let course {
                        NavigationLink { CourseMaterialsView(course: course) } label: {
                            Label("Materiali", systemImage: "folder")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        NavigationLink { CourseDetailView(course: course) } label: {
                            Label("Corso", systemImage: "books.vertical")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("Apri il corso")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Mean

    private func meanPanel(_ impact: ExamContext.MeanImpact) -> some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Media").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(impact.before, format: format).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(impact.after, format: format)
                    .font(style.dateFont.font(size: 26, weight: style.dateWeight))
                Text(impact.delta, format: format.sign(strategy: .always()))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(impact.delta >= 0 ? .green : .orange)
            }
            .monospacedDigit()
            Text("Stima sui voti del libretto pesati per CFU (\(impact.cfu) CFU per questo esame).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: - Other dates

    private func otherDates(_ sittings: [ExamSession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading("Altre date")
                .padding(.top, 10)
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(sittings) { sitting in
                            Button { withAnimation(.snappy) { exam = sitting } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sitting.date?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).locale(locale)) ?? "—")
                                        .font(.headline)
                                    Text(sitting.grade.map { $0.passed ? String(localized: "Superato · \($0.display)") : String(localized: "Non superato · \($0.display)") }
                                         ?? sitting.status.label)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }
}

// MARK: - Components

/// Opening and closing of enrolment on one line, with today's place on it.
private struct EnrolmentWindowBar: View {
    let opens: Date
    let closes: Date
    let tint: Color

    @Environment(\.locale) private var locale

    private var progress: Double {
        min(max(Date.now.timeIntervalSince(opens) / closes.timeIntervalSince(opens), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint).frame(width: max(proxy.size.width * progress, 6))
                }
            }
            .frame(height: 6)

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
    ExamDetailView(exam: MockData.examSessions()[0]).previewEnvironment()
}

#Preview("Esito") {
    ExamDetailView(exam: MockData.examSessions().first { $0.grade != nil }!).previewEnvironment()
}

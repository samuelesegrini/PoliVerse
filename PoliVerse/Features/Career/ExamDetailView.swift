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
    /// The sitting on screen, which the chips at the bottom can change.
    @State private var exam: ExamSession

    /// Opens the screen on one sitting.
    ///
    /// - Parameter exam: The sitting to show.
    init(exam: ExamSession) {
        _exam = State(initialValue: exam)
    }

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// Scaled, so the tile grows with the reader's text like the settings pictures.
    @ScaledMetric(relativeTo: .largeTitle) private var tileSide: CGFloat = 104
    /// Captured when the button is tapped, so the sheet keeps its event even
    /// if the sitting's start passes while it is open.
    @State private var calendarDraft: ExamCalendarEvent?
    /// The shared ``LiveActivityController``, from the environment.
    @Environment(LiveActivityController.self) private var liveActivity

    /// Only for a sitting still ahead: past ones have no use in a calendar.
    private var calendarEvent: ExamCalendarEvent? {
        guard (exam.date ?? .distantPast) > .now else { return nil }
        return ExamCalendarEvent(sitting: exam)
    }

    /// The sitting read against the rest of the career: its other dates, its libretto row, and what it would do to the average.
    private var context: ExamContext {
        ExamContext(exam: exam, sittings: career.sessions, libretto: career.libretto, now: .now)
    }

    /// The student's course page, when WeBeep or the plan lists it.
    private var course: Course? {
        courses.courses.first { exam.isOf(courseCode: $0.code ?? $0.id, courseName: $0.name) }
    }

    /// One table for the whole area: see ``CareerState``.
    static func accent(for status: ExamStatus) -> Color {
        switch status {
        case .graded(let grade):
            (grade.refusable ? CareerState.refusable
                : grade.passed ? .passed : .failed).tint
        case .enrolled: CareerState.booked.tint
        case .open: CareerState.enrolmentOpen.tint
        case .notYetOpen, .closed: CareerState.dormant.tint
        }
    }

    /// The view's content.
    var body: some View {
        let context = context
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sittingPanel(context)
                    actions

                    if LiveActivityController.canStart(exam) {
                        liveActivityButton
                    }

                    if let impact = context.meanImpact {
                        meanPanel(impact)
                    }

                    CorrectionsSection(exam: exam)

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
                        .foregroundStyle(CareerState.refusable.tint)
                }
            } else {
                // Enrolment is a write against the real university system,
                // which this app does not make: see
                // `docs/writes-to-university-systems.md`. It points at the
                // official services instead.
                Text("Le iscrizioni si gestiscono dai Servizi Online del Politecnico.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    /// Where the sitting stands, in one sentence.
    ///
    /// - Parameter context: The sitting in the career's context.
    /// - Returns: The sentence.
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

    /// The sitting's facts as label-and-value pairs, leaving out whatever the service did not say.
    ///
    /// - Parameter context: The sitting in the career's context.
    /// - Returns: The pairs, in reading order.
    private func facts(_ context: ExamContext) -> [(label: String, value: String)] {
        [
            exam.date.map { (String(localized: "Ora"), $0.formatted(.dateTime.hour().minute().locale(locale))) },
            exam.room.map { (String(localized: "Aula"), RoomNaming.bare($0)) },
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

    /// Following the exam on the Lock Screen, offered the same way the
    /// timetable offers it for a lecture: only on the day, only while there is
    /// something left to count down to, and never started by itself.
    @ViewBuilder
    private var liveActivityButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            if liveActivity.isShowing(exam) {
                Button(role: .destructive) {
                    liveActivity.end()
                } label: {
                    Label("Togli dalla schermata di blocco", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Button {
                    liveActivity.start(for: exam)
                } label: {
                    Label("Segui l'esame", systemImage: "pencil.and.list.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!liveActivity.isAvailable)
            }

            if let message = liveActivity.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !liveActivity.isAvailable {
                Text("Attiva le attività in tempo reale nelle impostazioni di iOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !liveActivity.isShowing(exam) {
                // The sitting's length is never published, so say the figure
                // is an assumption before it appears as a countdown.
                Text("Conto alla rovescia e aula sulla schermata di blocco. La durata è stimata in tre ore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mean

    /// What the mark does to the average: before, after, and the difference.
    ///
    /// - Parameter impact: The arithmetic, weighted by credits.
    /// - Returns: The panel.
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
                    .foregroundStyle(impact.delta >= 0 ? AnyShapeStyle(CareerState.passed.tint) : AnyShapeStyle(.secondary))
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

    /// The course's other sittings as chips, each one switching the screen to it.
    ///
    /// - Parameter sittings: The other sittings.
    /// - Returns: The row.
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
    /// When enrolment opened.
    let opens: Date
    /// When it closes.
    let closes: Date
    /// The bar's colour, taken from the sitting's state.
    let tint: Color

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// How far through the window today is, from 0 to 1.
    private var progress: Double {
        min(max(Date.now.timeIntervalSince(opens) / closes.timeIntervalSince(opens), 0), 1)
    }

    /// The view's content.
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

    /// One end of the bar: what the date is, and the date.
    ///
    /// - Parameters:
    ///   - title: What the date marks.
    ///   - date: The date.
    ///   - alignment: Which edge the pair sits against.
    /// - Returns: The label.
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

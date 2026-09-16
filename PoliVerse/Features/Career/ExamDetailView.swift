import SwiftUI

/// One exam sitting, thought of as what it is to a student: a moment with a
/// date, and a ticket to it.
///
/// What matters changes with time, so the page is built around where the
/// student is:
///
/// 1. **The ticket.** The sitting as an admission ticket — course and type on
///    top, then day, time and room as the fields of a boarding pass, and a
///    stub with the state. Once there is a mark, it lands on the ticket as a
///    stamp.
/// 2. **The route.** Enrolment opening, closing, the exam and the result as
///    stops on a line, with "you are here" between them.
/// 3. **Now.** One card that changes with the phase: the single number that
///    matters at that moment — days to close, to the exam, since it — and
///    only the actions that make sense then.
/// 4. **The mean**, once graded: before and after on the 18–30 scale.
/// 5. **The other sittings** and earlier attempts, as stubs to flip through.
///
/// How the exam works and its history close the page, for who reads on.
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

    /// The course's colour, as on its page; by name when no course matches,
    /// as Oggi colours its lessons.
    private var courseColour: Color {
        course.map(Theme.accent(for:)) ?? Theme.courseAccents[TodayDigest.colourIndex(for: exam.courseName)]
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
        let phase = ExamPhase(exam: exam, now: .now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    ExamTicket(exam: exam, phase: phase, colour: courseColour, cfu: context.librettoEntry?.cfu)

                    ExamRoute(exam: exam, phase: phase, colour: courseColour)

                    nowCard(phase, context: context)

                    if let impact = context.meanImpact {
                        MeanScale(impact: impact, colour: courseColour)
                    }

                    let others = context.otherUpcoming + context.previousAttempts
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            LookHeading(exam.grade == nil ? "Le altre date" : "Gli altri appelli")
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach(others) { sitting in
                                        Button { withAnimation(.snappy) { exam = sitting } } label: {
                                            SittingStub(sitting: sitting, colour: courseColour)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                            }
                            .scrollIndicators(.hidden)
                            .padding(.horizontal, -20)
                        }
                    }

                    ExamFormatSection(exam: exam)

                    ExamTimelineSection(exam: exam)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: exam.id)
            }
            .lookPage()
            .sheet(item: $calendarDraft) { AddToCalendarSheet(event: $0).ignoresSafeArea() }
            // The ticket names the sitting; the bar only closes it.
            .navigationTitle(exam.courseName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(verbatim: "") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    // MARK: - Now

    /// The one thing that matters at this point, as a number and a sentence,
    /// with only the actions that make sense now.
    private func nowCard(_ phase: ExamPhase, context: ExamContext) -> some View {
        let focus = focus(for: phase, context: context)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Adesso")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(courseColour)

            HStack(alignment: .center, spacing: 16) {
                if let number = focus.number {
                    Text(verbatim: number)
                        .font(style.dateFont.font(size: 64, weight: style.dateWeight))
                        .foregroundStyle(courseColour)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .fixedSize()
                        .contentTransition(.numericText())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(focus.headline)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = focus.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                if let event = calendarEvent {
                    Button { calendarDraft = event } label: {
                        actionLabel("Aggiungi al Calendario", "calendar.badge.plus")
                    }
                    .buttonStyle(.glassProminent)
                }
                if let course {
                    if phase.isBeforeResult {
                        NavigationLink { CourseMaterialsView(course: course) } label: {
                            actionLabel("Ripassa dai materiali", "folder")
                        }
                        .buttonStyle(.glass)
                    }
                    NavigationLink { CourseDetailView(course: course) } label: {
                        actionLabel("Apri il corso", "books.vertical")
                    }
                    .buttonStyle(.glass)
                }
            }
            .tint(courseColour)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard(cornerRadius: 28)
    }

    private func actionLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private struct Focus {
        var number: String?
        let headline: String
        var detail: String?
    }

    private func days(to date: Date) -> Int {
        let calendar = PoliMiDate.romeCalendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    private func focus(for phase: ExamPhase, context: ExamContext) -> Focus {
        let long = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(locale)
        let time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        switch phase {
        case .waitingToOpen:
            guard let opens = exam.enrolmentOpens else {
                return Focus(headline: String(localized: "Iscrizioni non ancora aperte"),
                             detail: String(localized: "La data di apertura non è ancora pubblicata."))
            }
            let count = max(days(to: opens), 0)
            return Focus(number: "\(count)",
                         headline: count == 1 ? String(localized: "giorno all'apertura delle iscrizioni")
                             : String(localized: "giorni all'apertura delle iscrizioni"),
                         detail: String(localized: "Aprono \(opens.formatted(long))."))
        case .enrolmentOpen:
            guard let closes = exam.enrolmentCloses else {
                return Focus(headline: String(localized: "Puoi iscriverti"),
                             detail: String(localized: "Dai Servizi Online del Politecnico."))
            }
            let count = max(days(to: closes), 0)
            if count == 0 {
                return Focus(number: closes.formatted(time), headline: String(localized: "Ultimo giorno per iscriverti"),
                             detail: String(localized: "Ci si iscrive dai Servizi Online del Politecnico."))
            }
            return Focus(number: "\(count)",
                         headline: count == 1 ? String(localized: "giorno per iscriverti") : String(localized: "giorni per iscriverti"),
                         detail: String(localized: "Chiudono \(closes.formatted(long)). Ci si iscrive dai Servizi Online del Politecnico."))
        case .enrolled:
            guard let date = exam.date else {
                return Focus(headline: String(localized: "Sei iscritto"), detail: String(localized: "La data non è ancora pubblicata."))
            }
            let count = max(days(to: date), 0)
            return Focus(number: "\(count)",
                         headline: count == 1 ? String(localized: "giorno all'esame") : String(localized: "giorni all'esame"),
                         detail: String(localized: "Sei iscritto: \(date.formatted(long)) alle \(date.formatted(time))."))
        case .enrolmentClosed:
            if let date = context.otherUpcoming.first?.date {
                let count = max(days(to: date), 0)
                return Focus(number: "\(count)",
                             headline: count == 1 ? String(localized: "giorno al prossimo appello")
                                 : String(localized: "giorni al prossimo appello"),
                             detail: String(localized: "Le iscrizioni a questo sono chiuse. Il prossimo è \(date.formatted(long))."))
            }
            return Focus(headline: String(localized: "Iscrizioni chiuse"),
                         detail: String(localized: "Non risultano altri appelli in programma per questo corso."))
        case .examDay:
            return Focus(number: exam.date?.formatted(time),
                         headline: String(localized: "L'esame è oggi"),
                         detail: [exam.room.map { String(localized: "In aula \($0)") }, exam.kind?.nonEmpty]
                             .compactMap { $0 }.joined(separator: " · ").nonEmpty)
        case .awaitingResult:
            let count = exam.date.map { max(-days(to: $0), 0) }
            return Focus(number: count.map { "\($0)" },
                         headline: count == 1 ? String(localized: "giorno dall'esame") : String(localized: "giorni dall'esame"),
                         detail: String(localized: "L'esito non è ancora pubblicato. Quando arriva lo trovi qui e tra le novità."))
        case .passed(let grade):
            if grade.refusable {
                return Focus(headline: String(localized: "Puoi accettarlo o rifiutarlo"),
                             detail: String(localized: "Il voto si rifiuta dai Servizi Online, finché la finestra è aperta."))
            }
            if context.librettoEntry?.isPassed == true {
                return Focus(headline: String(localized: "Registrato nel libretto"),
                             detail: exam.hasCorrections ? String(localized: "L'elaborato corretto è consultabile sui Servizi Online.") : nil)
            }
            return Focus(headline: String(localized: "Superato"),
                         detail: String(localized: "In attesa di registrazione nel libretto."))
        case .failed:
            if let date = context.otherUpcoming.first?.date {
                let count = max(days(to: date), 0)
                return Focus(number: "\(count)",
                             headline: count == 1 ? String(localized: "giorno al prossimo tentativo")
                                 : String(localized: "giorni al prossimo tentativo"),
                             detail: String(localized: "Non entra nella media. Il prossimo appello è \(date.formatted(long))."))
            }
            return Focus(headline: String(localized: "Non superato"),
                         detail: String(localized: "Non entra nella media: puoi ripresentarti a un prossimo appello."))
        }
    }
}

// MARK: - Phase

/// Where the student stands with a sitting.
enum ExamPhase: Equatable {
    case waitingToOpen, enrolmentOpen, enrolmentClosed, enrolled, examDay, awaitingResult
    case passed(ExamGrade), failed(ExamGrade)

    init(exam: ExamSession, now: Date) {
        let calendar = PoliMiDate.romeCalendar
        if let grade = exam.grade {
            self = grade.passed ? .passed(grade) : .failed(grade)
        } else if let date = exam.date, calendar.isDate(date, inSameDayAs: now) {
            self = .examDay
        } else if let date = exam.date, date < now {
            self = .awaitingResult
        } else {
            switch exam.status {
            case .notYetOpen: self = .waitingToOpen
            case .open: self = .enrolmentOpen
            case .enrolled: self = .enrolled
            case .closed, .graded: self = .enrolmentClosed
            }
        }
    }

    /// How many stops of the route are behind: enrolment opening, closing,
    /// the exam, the result.
    var stopsPassed: Int {
        switch self {
        case .waitingToOpen: 0
        case .enrolmentOpen: 1
        case .enrolled, .enrolmentClosed: 2
        case .examDay, .awaitingResult: 3
        case .passed, .failed: 4
        }
    }

    var isBeforeResult: Bool {
        switch self {
        case .awaitingResult, .passed: false
        default: true
        }
    }

    /// The word on the ticket's stub.
    var stamp: LocalizedStringKey {
        switch self {
        case .waitingToOpen: "In arrivo"
        case .enrolmentOpen: "Iscrizioni aperte"
        case .enrolmentClosed: "Iscrizioni chiuse"
        case .enrolled: "Iscritto"
        case .examDay: "Oggi"
        case .awaitingResult: "In attesa dell'esito"
        case .passed: "Superato"
        case .failed: "Non superato"
        }
    }
}

// MARK: - Ticket

/// The sitting as an admission ticket: a coloured top with the course and the
/// fields of the day, a torn edge, and a stub with the state. A mark, once
/// there is one, is stamped across it.
private struct ExamTicket: View {
    let exam: ExamSession
    let phase: ExamPhase
    let colour: Color
    let cfu: Int?

    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    private static let notch: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            top
                .background {
                    TicketHalf(edge: .bottom, notch: Self.notch)
                        .fill(colour)
                        .visualEffect { content, proxy in
                            content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.45)))
                        }
                }
            // The tear: dashes between the two notches.
            TearLine()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .foregroundStyle(colour.opacity(0.6))
                .frame(height: 1.5)
                .padding(.horizontal, Self.notch + 6)
            stub
                .background {
                    TicketHalf(edge: .top, notch: Self.notch)
                        .fill(colour.opacity(0.14))
                }
        }
        .shadow(color: colour.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.kind?.nonEmpty ?? String(localized: "Appello"))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .opacity(0.8)
                Text(exam.courseName)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let teacher = exam.teacher {
                    Text(teacher).font(.subheadline).opacity(0.85)
                }
            }

            // The fields of a boarding pass: a small label over a large value.
            // Once sat, the room no longer matters: the mark is stamped in
            // its place.
            HStack(alignment: .center, spacing: 12) {
                field("Giorno", exam.date?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? "—")
                field("Ora", exam.date?.formatted(.dateTime.hour().minute().locale(locale)) ?? "—")
                if let grade = exam.grade {
                    GradeStamp(grade: grade)
                        .frame(maxWidth: .infinity)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                } else {
                    field("Aula", exam.room ?? "—", lines: 2)
                }
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ label: LocalizedStringKey, _ value: String, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .kerning(1)
                .opacity(0.75)
            Text(verbatim: value)
                .font(style.dateFont.font(size: 24, weight: style.dateWeight))
                .lineLimit(lines)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stub: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(colour).frame(width: 8, height: 8)
                Text(phase.stamp)
            }
            .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text([exam.enrolledCount.flatMap { $0 > 0 ? String(localized: "\($0) iscritti") : nil },
                  cfu.flatMap { $0 > 0 ? String(localized: "\($0) CFU") : nil },
                  exam.courseCode].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }
}

/// Half a ticket: rounded on its outer edge, with a semicircle bitten out of
/// both sides where it tears.
private nonisolated struct TicketHalf: Shape {
    enum Edge { case top, bottom }
    let edge: Edge
    let notch: CGFloat
    var corner: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let tearY = edge == .bottom ? rect.maxY : rect.minY
        let outerY = edge == .bottom ? rect.minY : rect.maxY
        let inward: CGFloat = edge == .bottom ? -1 : 1   // from the tear towards the outer edge
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + notch, y: tearY))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: tearY))
        // Right notch: a quarter circle from the tear to the side.
        path.addArc(center: CGPoint(x: rect.maxX, y: tearY), radius: notch,
                    startAngle: .degrees(180), endAngle: .degrees(edge == .bottom ? 270 : 90),
                    clockwise: edge == .top)
        path.addLine(to: CGPoint(x: rect.maxX, y: outerY - inward * corner))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - corner, y: outerY), control: CGPoint(x: rect.maxX, y: outerY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: outerY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: outerY - inward * corner), control: CGPoint(x: rect.minX, y: outerY))
        path.addLine(to: CGPoint(x: rect.minX, y: tearY + inward * notch))
        // Left notch, back to the tear.
        path.addArc(center: CGPoint(x: rect.minX, y: tearY), radius: notch,
                    startAngle: .degrees(edge == .bottom ? 270 : 90), endAngle: .degrees(360),
                    clockwise: edge == .top)
        path.closeSubpath()
        return path
    }
}

private nonisolated struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/// The mark as an ink stamp on the ticket, a little crooked, as one pressed
/// by hand.
private struct GradeStamp: View {
    let grade: ExamGrade
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        let ink: Color = grade.passed ? Color(red: 0.1, green: 0.5, blue: 0.28) : Color(red: 0.76, green: 0.14, blue: 0.2)
        VStack(spacing: 0) {
            Text(verbatim: grade.display)
                .font(style.dateFont.font(size: 36, weight: style.dateWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(grade.passed ? "Superato" : "Non superato")
                .font(.system(size: 9, weight: .heavy))
                .textCase(.uppercase)
                .kerning(1.1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(width: 96, height: 80)
        .background(Color.white.opacity(0.94), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ink, lineWidth: 2.5).padding(4)
        }
        .rotationEffect(.degrees(-9))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Voto \(grade.display)"))
    }
}

// MARK: - Route

/// Enrolment opening, closing, the exam and the result as stops on a line,
/// with the student's place on it.
private struct ExamRoute: View {
    let exam: ExamSession
    let phase: ExamPhase
    let colour: Color

    @Environment(\.locale) private var locale

    private struct Stop: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let date: Date?
    }

    private var stops: [Stop] {
        [Stop(id: 0, title: "Apertura", date: exam.enrolmentOpens),
         Stop(id: 1, title: "Chiusura", date: exam.enrolmentCloses),
         Stop(id: 2, title: "Esame", date: exam.date),
         Stop(id: 3, title: "Esito", date: nil)]
    }

    var body: some View {
        let passed = phase.stopsPassed
        VStack(alignment: .leading, spacing: 12) {
            LookHeading("Il percorso")
            GeometryReader { proxy in
                let step = proxy.size.width / CGFloat(stops.count)
                let start = step / 2, end = proxy.size.width - step / 2
                // Halfway between the last stop passed and the next.
                let progress = min(max(CGFloat(passed) - 0.5, 0), CGFloat(stops.count - 1))
                let here = start + (end - start) * progress / CGFloat(stops.count - 1)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.quaternary)
                        .frame(width: end - start, height: 4)
                        .offset(x: start, y: 9)
                    Capsule().fill(colour)
                        .frame(width: max(here - start, 0), height: 4)
                        .offset(x: start, y: 9)
                    ForEach(stops) { stop in
                        let done = stop.id < passed
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(done ? AnyShapeStyle(colour) : AnyShapeStyle(.background))
                                Circle().strokeBorder(done ? colour : Color.secondary.opacity(0.4), lineWidth: 2.5)
                                if done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(Theme.onAccent)
                                }
                            }
                            .frame(width: 22, height: 22)
                            Text(stop.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(done ? .primary : .secondary)
                            Text(verbatim: stop.date?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? " ")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(width: step)
                        .offset(x: step * CGFloat(stop.id))
                    }
                    if passed > 0 && passed < stops.count {
                        HereMarker(colour: colour)
                            .offset(x: here - 8, y: 3)
                    }
                }
            }
            .frame(height: 64)
            .padding(.vertical, 18)
            .padding(.horizontal, 6)
            .lookCard(cornerRadius: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Percorso dell'appello: \(Text(phase.stamp))"))
    }
}

/// A dot that breathes, where the student is on the route.
private struct HereMarker: View {
    let colour: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle().fill(colour.opacity(0.35))
                    .phaseAnimator([1.0, 2.2]) { view, scale in
                        view.scaleEffect(scale).opacity(2.3 - scale)
                    } animation: { _ in .easeInOut(duration: 1.2) }
            }
            Circle().fill(colour)
            Circle().fill(.white).padding(4)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Mean

/// The mean before and after this mark on the scale marks live on, so a
/// tenth reads as the small step it is.
private struct MeanScale: View {
    let impact: ExamContext.MeanImpact
    let colour: Color
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    private func position(_ value: Double, in width: CGFloat) -> CGFloat {
        width * CGFloat((min(max(value, 18), 30) - 18) / 12)
    }

    var body: some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        VStack(alignment: .leading, spacing: 12) {
            LookHeading("La tua media")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(impact.before, format: format)
                        .font(style.dateFont.font(size: 22, weight: style.dateWeight))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(impact.after, format: format)
                        .font(style.dateFont.font(size: 40, weight: style.dateWeight))
                        .foregroundStyle(colour)
                    Spacer(minLength: 8)
                    Text(impact.delta, format: format.sign(strategy: .always()))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(impact.delta >= 0 ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((impact.delta >= 0 ? Color.green : .orange).opacity(0.15), in: .capsule)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let before = position(impact.before, in: width), after = position(impact.after, in: width)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary).frame(height: 8)
                            Capsule().fill(colour.opacity(0.4))
                                .frame(width: max(abs(after - before), 2), height: 8)
                                .offset(x: min(before, after))
                            Circle().strokeBorder(.secondary, lineWidth: 2)
                                .background(Circle().fill(.background))
                                .frame(width: 14, height: 14)
                                .offset(x: before - 7)
                            Circle().fill(colour)
                                .frame(width: 18, height: 18)
                                .offset(x: after - 9)
                        }
                        .frame(height: 18)
                    }
                    .frame(height: 18)
                    HStack {
                        Text(verbatim: "18"); Spacer(); Text(verbatim: "24"); Spacer(); Text(verbatim: "30")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Text("Stima sui voti del libretto pesati per CFU, con \(impact.cfu) CFU per questo esame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .lookCard(cornerRadius: 24)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Other sittings

/// Another sitting as the stub of its ticket: the day large, its type and
/// where it stands — the mark, for one already sat.
private struct SittingStub: View {
    let sitting: ExamSession
    let colour: Color

    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: sitting.date?.formatted(.dateTime.day().locale(locale)) ?? "—")
                    .font(style.dateFont.font(size: 32, weight: style.dateWeight))
                Text(verbatim: (sitting.date?.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(locale)) ?? "").uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            TearLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.tertiary)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(sitting.kind?.nonEmpty ?? String(localized: "Appello"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let grade = sitting.grade {
                    Text(grade.passed ? "Superato · \(grade.display)" : "Non superato · \(grade.display)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(grade.passed ? .green : .red)
                } else {
                    Text(sitting.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 20)
        .padding([.trailing, .vertical], 16)
        .frame(width: 168, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule().fill(sitting.grade == nil ? colour : Color.secondary.opacity(0.5))
                .frame(width: 4)
                .padding(.vertical, 16)
                .padding(.leading, 8)
        }
        .lookCard(cornerRadius: 22)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Appello") {
    ExamDetailView(exam: MockData.examSessions()[0]).previewEnvironment()
}

#Preview("Esito") {
    ExamDetailView(exam: MockData.examSessions().first { $0.grade != nil }!).previewEnvironment()
}

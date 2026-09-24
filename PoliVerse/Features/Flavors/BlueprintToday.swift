import SwiftUI

/// Oggi in Blueprint: the day as a sheet of a technical drawing. The date is
/// the figure's title, the next lesson box A with its hours as a dimension
/// line, the rest of the day table B, and what is due box C.
struct BlueprintToday: View {
    /// The day the page is about.
    let day: Date
    /// The look, already resolved.
    let style: TodayStyle
    /// Rows open their lesson or sitting: on the page, not in Personalizza.
    var opensDetails = true

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var updates
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The reader's text size, which stacks box C's cells.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The Politecnico's calendar.
    private let calendar = PoliMiDate.romeCalendar

    /// The view's content.
    var body: some View {
        let palette = BlueprintPalette(style)
        TimelineView(.everyMinute) { context in
            let now = context.date
            let lessons = TodayDigest.timetable(events: agenda.events, day: day)
            let isToday = calendar.isDate(day, inSameDayAs: now)
            let current = isToday ? CurrentClass.pick(from: agenda.events, now: now) : nil
            let next = isToday ? current?.event : lessons.first
            let later = lessons.filter { lesson in
                guard let next else { return !isToday || lesson.end > now }
                return lesson.start > next.start
            }
            VStack(alignment: .leading, spacing: 26) {
                header(lessons: lessons.count)
                if let next {
                    nextBox(next, ongoing: current?.isOngoing ?? false, isToday: isToday, now: now, palette: palette)
                } else {
                    BlueprintBox(label: "A · \(String(localized: "OGGI"))", dashed: true) {
                        Text(lessons.isEmpty ? "NESSUNA LEZIONE" : "LEZIONI FINITE")
                            .font(.blueprint(22, bold: true, relativeTo: .title2))
                    }
                }
                if !later.isEmpty { laterTable(later) }
                todo(now: now, palette: palette)
            }
            .foregroundStyle(palette.ink)
        }
    }

    // MARK: - The title

    /// "FIG. 23 — MERCOLEDÌ" over the date, with the day's count on a dimension line.
    private func header(lessons: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FIG. \(day.formatted(.dateTime.day().locale(locale))) — \(day.formatted(.dateTime.weekday(.wide).locale(locale)).uppercased())")
                .font(.blueprint(12, relativeTo: .caption1))
                .tracking(2)
                .opacity(0.75)
            // Day and month as a drawing numbers its sheets, whatever the
            // locale writes between them.
            Text(verbatim: day.formatted(.dateTime.day(.twoDigits).locale(locale)) + "."
                 + day.formatted(.dateTime.month(.twoDigits).locale(locale)))
                .font(.blueprint(72, bold: true, relativeTo: .largeTitle))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            HStack(spacing: 8) {
                Rectangle().frame(height: 1)
                Text(lessons == 1 ? String(localized: "1 LEZIONE") : String(localized: "\(lessons) LEZIONI"))
                    .font(.blueprint(11, relativeTo: .caption2))
                    .fixedSize()
                Rectangle().frame(height: 1)
            }
            .opacity(0.72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Box A

    /// The lesson under way or next, with its hours as a dimension line.
    private func nextBox(_ lesson: AgendaEvent, ongoing: Bool, isToday: Bool, now: Date,
                         palette: BlueprintPalette) -> some View {
        let time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        let label = ongoing ? String(localized: "ADESSO") : isToday ? String(localized: "PROSSIMA") : String(localized: "LA PRIMA")
        return BlueprintBox(label: "A · \(label)") {
            VStack(alignment: .leading, spacing: 10) {
                Text(ongoing ? String(localized: "FINO ALLE \(lesson.end.formatted(time))")
                     : isToday ? countdown(to: lesson.start, from: now)
                     : String(localized: "ALLE \(lesson.start.formatted(time))"))
                    .font(.blueprint(32, bold: true, relativeTo: .largeTitle))
                    .foregroundStyle(ongoing ? palette.mark : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(lesson.title.uppercased())
                    .font(.blueprint(16, bold: true, relativeTo: .headline))
                    .lineLimit(2)
                BlueprintDimension(start: lesson.start.formatted(time), end: lesson.end.formatted(time))
                if let room = lesson.roomLabel {
                    Text("└── \(room.lowercased())")
                        .font(.blueprint(12, relativeTo: .caption1))
                        .opacity(0.75)
                }
                if opensDetails {
                    Button {
                        shell.present { shell.detail = .event(lesson) }
                    } label: {
                        Text("DETTAGLI E AULA")
                            .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                            .tracking(1)
                            .foregroundStyle(palette.paper)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "T–25 MIN", counting down to a start.
    private func countdown(to start: Date, from now: Date) -> String {
        let minutes = max(Int(start.timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return String(localized: "T–\(minutes) MIN") }
        return String(localized: "T–\(Int((Double(minutes) / 60).rounded())) H")
    }

    // MARK: - Table B

    /// The rest of the day as a table: the time, then what and where.
    private func laterTable(_ lessons: [AgendaEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueprintHeading(title: String(localized: "B · POI"))
            VStack(spacing: 0) {
                BlueprintRule()
                ForEach(lessons) { lesson in
                    opening(.event(lesson)) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(lesson.start.formatted(.dateTime.hour().minute().locale(locale)))
                                .font(.blueprint(15, bold: true, relativeTo: .body))
                                .frame(minWidth: 52, alignment: .leading)
                            Rectangle().frame(width: 1).opacity(0.55).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.title.uppercased())
                                    .font(.blueprint(14, relativeTo: .subheadline))
                                    .lineLimit(2)
                                if let room = lesson.roomLabel {
                                    Text(room.lowercased())
                                        .font(.blueprint(12, relativeTo: .caption1))
                                        .opacity(0.72)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(.rect)
                        .accessibilityElement(children: .combine)
                    }
                    BlueprintRule()
                }
            }
        }
    }

    // MARK: - Box C

    /// What is due: WeBeep's hand-ins and the one enrolment closing soonest,
    /// each in a cell of the box.
    @ViewBuilder
    private func todo(now: Date, palette: BlueprintPalette) -> some View {
        let deadlines = TodayDigest.deadlines(updates.deadlines, now: now, limit: 2)
        let enrolment = CareerDeadline.all(in: career.sessions, now: now).first { $0.kind == .enrolmentClosing }
        if !deadlines.isEmpty || enrolment != nil {
            let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().locale(locale)
            let count = deadlines.count + (enrolment == nil ? 0 : 1)
            let columns = typeSize.isAccessibilitySize ? 1 : min(count, 2)
            VStack(alignment: .leading, spacing: 8) {
                BlueprintHeading(title: String(localized: "C · DA FARE"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 0) {
                    ForEach(deadlines) { deadline in
                        opening(.deadline(deadline)) {
                            cell(kicker: String(localized: "CONSEGNA · \(deadline.due.formatted(day).uppercased())"),
                                 title: deadline.name, colour: palette.faint)
                        }
                    }
                    if let enrolment, let closes = enrolment.at {
                        opening(.exam(enrolment.exam)) {
                            cell(kicker: String(localized: "ISCRIZIONI · \(closes.formatted(day).uppercased())"),
                                 title: enrolment.exam.courseName, colour: palette.mark)
                        }
                    }
                }
                .overlay { Rectangle().strokeBorder(.white.opacity(0.95), lineWidth: 2) }
            }
        }
    }

    /// One cell of box C.
    private func cell(kicker: String, title: String, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(.blueprint(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(colour)
            Text(title)
                .font(.blueprint(13, bold: true, relativeTo: .subheadline))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .overlay { Rectangle().stroke(.white.opacity(0.6), lineWidth: 1) }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// A row as a button opening its detail, or as it is in Personalizza.
    @ViewBuilder
    private func opening(_ detail: TodayDetail, @ViewBuilder content: () -> some View) -> some View {
        if opensDetails {
            Button { shell.present { shell.detail = detail } } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

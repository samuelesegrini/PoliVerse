import SwiftUI

/// Oggi in Giocherelloso: the day's number huge, the next lesson on a card in
/// the page's colour with the whole day drawn under it, the lessons after it
/// as cards in their courses' colours, and what is due.
///
/// Replaces the date and the sections, not the bar: the day stepper and the
/// menus are the same in every Flavor.
struct PlayfulToday: View {
    /// The day the page is about.
    let day: Date
    /// The look, already resolved.
    let style: TodayStyle
    /// Cards open their lesson or sitting: on the page, not in Personalizza,
    /// where a tap opens the Flavor's knobs.
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
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The reader's text size, which folds the grid into one column.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The Politecnico's calendar, which every day here is counted in.
    private let calendar = PoliMiDate.romeCalendar

    /// The view's content.
    var body: some View {
        let palette = PlayfulPalette(style, scheme: scheme)
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
            VStack(alignment: .leading, spacing: 22) {
                header(lessons: lessons, palette: palette)
                if let next {
                    nextCard(next, ongoing: current?.isOngoing ?? false, isToday: isToday,
                             lessons: lessons, now: now, palette: palette)
                } else {
                    freeDay(palette: palette, isToday: isToday, hadLessons: !lessons.isEmpty)
                }
                if !later.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        PlayfulHeading("Poi")
                        laterGrid(later)
                    }
                }
                todo(now: now, palette: palette)
            }
        }
    }

    // MARK: - The date

    /// The day's number huge in the page's colour, the weekday and month beside it.
    private func header(lessons: [AgendaEvent], palette: PlayfulPalette) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(day.formatted(.dateTime.day().locale(locale)))
                .font(.playful(112, relativeTo: .largeTitle))
                .foregroundStyle(palette.main)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide).locale(locale)).uppercased())
                    .font(.playful(13, relativeTo: .caption))
                    .tracking(2)
                    .foregroundStyle(palette.secondText)
                Text(day.formatted(.dateTime.month(.wide).locale(locale)))
                    .font(.playful(28, relativeTo: .title))
                Text(summary(lessons: lessons.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "3 lezioni", or that there are none.
    private func summary(lessons: Int) -> String {
        switch lessons {
        case 0: String(localized: "Nessuna lezione")
        case 1: String(localized: "1 lezione")
        default: String(localized: "\(lessons) lezioni")
        }
    }

    // MARK: - The next lesson

    /// The lesson under way or next, on a card in the page's colour, with the
    /// day drawn under it and the now line on it.
    private func nextCard(_ lesson: AgendaEvent, ongoing: Bool, isToday: Bool, lessons: [AgendaEvent],
                          now: Date, palette: PlayfulPalette) -> some View {
        let time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        let kicker = ongoing ? String(localized: "ADESSO")
            : isToday ? String(localized: "PROSSIMA LEZIONE") : String(localized: "LA PRIMA LEZIONE")
        let big = ongoing ? String(localized: "fino alle \(lesson.end.formatted(time))")
            : isToday ? countdown(to: lesson.start, from: now) : String(localized: "alle \(lesson.start.formatted(time))")
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                PlayfulKicker(text: kicker, colour: palette.onMain.opacity(0.75))
                Text(big)
                    .font(.playful(42, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text([lesson.start.formatted(time) + "–" + lesson.end.formatted(time), lesson.roomLabel]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .opacity(0.85)
            }
            DayBar(lessons: lessons, highlighted: lesson, now: isToday ? now : nil, palette: palette)
            if opensDetails {
                Button {
                    shell.present { shell.detail = .event(lesson) }
                } label: {
                    Label("Dettagli e aula", systemImage: "location.north.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(palette.onSecond)
                        .background(palette.second, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(palette.onMain)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.main, in: .rect(cornerRadius: 28, style: .continuous))
        .shadow(color: palette.main.opacity(0.3), radius: 16, y: 8)
        .playfulLean(0, in: style)
    }

    /// "tra 25 min", "tra 2 h", as the card counts down to a start.
    private func countdown(to start: Date, from now: Date) -> String {
        let minutes = max(Int(start.timeIntervalSince(now) / 60), 0)
        if minutes < 1 { return String(localized: "adesso") }
        if minutes < 60 { return String(localized: "tra \(minutes) min") }
        let hours = Int((Double(minutes) / 60).rounded())
        return String(localized: "tra \(hours) h")
    }

    /// A day with nothing left to go to, said on the same card.
    private func freeDay(palette: PlayfulPalette, isToday: Bool, hadLessons: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PlayfulKicker(text: String(localized: "OGGI"), colour: palette.onMain.opacity(0.75))
            Text(hadLessons ? "Lezioni finite" : "Giornata libera")
                .font(.playful(36, relativeTo: .largeTitle))
            Text(hadLessons ? "Per oggi è tutto." : "Nessuna lezione in calendario.")
                .font(.subheadline)
                .opacity(0.85)
        }
        .foregroundStyle(palette.onMain)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.main, in: .rect(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Later

    /// The lessons after the next one, as cards in their courses' colours.
    private func laterGrid(_ lessons: [AgendaEvent]) -> some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                opening(.event(lesson)) {
                    laterCard(lesson)
                }
                .playfulLean(index + 1, in: style)
            }
        }
    }

    /// One lesson later in the day: its time big, its name and room.
    private func laterCard(_ lesson: AgendaEvent) -> some View {
        let colour = Theme.courseAccents[TodayDigest.colourIndex(for: lesson.title)]
        return VStack(alignment: .leading, spacing: 6) {
            Text(lesson.start.formatted(.dateTime.hour().minute().locale(locale)))
                .font(.playful(28, relativeTo: .title))
                .monospacedDigit()
            Text(lesson.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let room = lesson.roomLabel {
                Text(room).font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(colour, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - To do

    /// WeBeep's next hand-ins and the one career deadline that matters most,
    /// each with its date on a badge. The career one only points at its sitting:
    /// Carriera is where it is dealt with.
    @ViewBuilder
    private func todo(now: Date, palette: PlayfulPalette) -> some View {
        let deadlines = TodayDigest.deadlines(updates.deadlines, now: now, limit: 2)
        let career = CareerDeadline.all(in: career.sessions, now: now).first { $0.kind == .enrolmentClosing }
        if !deadlines.isEmpty || career != nil {
            VStack(alignment: .leading, spacing: 10) {
                PlayfulHeading("Da fare")
                VStack(spacing: 0) {
                    ForEach(deadlines) { deadline in
                        opening(.deadline(deadline)) {
                            todoRow(date: deadline.due, title: deadline.name, detail: deadline.courseName,
                                    badge: Theme.courseAccents[TodayDigest.colourIndex(for: deadline.courseName)].opacity(0.2),
                                    ink: .primary)
                        }
                        if deadline.id != deadlines.last?.id || career != nil {
                            DashedDivider()
                        }
                    }
                    if let career, let closes = career.at {
                        opening(.exam(career.exam)) {
                            todoRow(date: closes,
                                    title: String(localized: "Chiudono le iscrizioni a \(career.exam.courseName)"),
                                    detail: String(localized: "Iscriviti da Carriera"),
                                    badge: palette.secondWash, ink: palette.secondText)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .todayMaterial(style.material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: 22)
            }
        }
    }

    /// One thing to do: a date badge, what it is, where from.
    private func todoRow(date: Date, title: String, detail: String, badge: Color, ink: Color) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased())
                    .font(.playful(9, relativeTo: .caption2))
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.playful(17, relativeTo: .headline))
            }
            .foregroundStyle(ink)
            .frame(width: 42, height: 42)
            .background(badge, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if opensDetails {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// A card as a button opening its detail, or as it is in Personalizza.
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

/// The day as a strip: each lesson a block between its hours, the next one
/// solid, and a line where now is.
private struct DayBar: View {
    /// The day's lessons.
    let lessons: [AgendaEvent]
    /// The lesson the card is about.
    let highlighted: AgendaEvent
    /// Now, when the day is today.
    let now: Date?
    /// The card's colours.
    let palette: PlayfulPalette

    /// The Politecnico's calendar.
    private let calendar = PoliMiDate.romeCalendar

    /// The view's content.
    var body: some View {
        let (start, end) = range
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let x = { (date: Date) -> CGFloat in
                    CGFloat((hour(date) - start) / (end - start)) * proxy.size.width
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.onMain.opacity(0.12))
                    ForEach(lessons) { lesson in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.onMain.opacity(lesson.id == highlighted.id ? 1 : 0.45))
                            .frame(width: max(x(lesson.end) - x(lesson.start) - 2, 6), height: 16)
                            .offset(x: x(lesson.start) + 1)
                    }
                    if let now, hour(now) > start, hour(now) < end {
                        Capsule()
                            .fill(palette.second)
                            .frame(width: 3, height: 30)
                            .offset(x: x(now) - 1.5)
                    }
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            HStack {
                ForEach(ticks, id: \.self) { tick in
                    Text("\(tick)")
                    if tick != ticks.last { Spacer(minLength: 0) }
                }
            }
            .font(.caption2.monospacedDigit())
            .opacity(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("La giornata"))
        .accessibilityValue(Text(summary))
    }

    /// The hours the strip spans: 8 to 19, stretched to fit an earlier or later lesson.
    private var range: (Double, Double) {
        let first = lessons.map { hour($0.start) }.min() ?? 8
        let last = lessons.map { hour($0.end) }.max() ?? 19
        return (min(8, first.rounded(.down)), max(19, last.rounded(.up)))
    }

    /// Every other hour along the strip.
    private var ticks: [Int] {
        let (start, end) = range
        return Array(stride(from: Int(start), through: Int(end), by: 2))
    }

    /// A time as hours since midnight.
    private func hour(_ date: Date) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// The lessons in words, for VoiceOver.
    private var summary: String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        return lessons.map { "\($0.title), \($0.start.formatted(time))–\($0.end.formatted(time))" }
            .joined(separator: "; ")
    }
}

/// A dashed line between a ticket's rows.
private struct DashedDivider: View {
    /// The view's content.
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .foregroundStyle(.separator)
    }
}

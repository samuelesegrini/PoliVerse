#if os(macOS)
import SwiftUI

/// Oggi on the Mac: the iPhone's landing arranged for a wide window.
///
/// Two columns. The left one answers "what now": the date, the class in progress with
/// its countdown, and the day as a horizontal timeline. The right one answers "what
/// next": deadlines and the next sitting, what changed in the courses, and the career
/// figures. Rows open the same detail sheets the iPhone uses, through ``ShellState``.
struct MacTodayView: View {
    @Environment(Session.self) private var session
    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.shell) private var shell
    @Environment(\.look) private var look

    /// Moved on every minute, so the countdown's progress and the timeline's "now" line
    /// keep up.
    @State private var now = Date.now

    private var calendar: Calendar { PoliMiDate.romeCalendar }

    #if DEBUG
    /// Whether `-OggiDayOffset` was applied, so a second appearance does not move again.
    private static var appliedDayOffset = false
    #endif

    /// The day on show: today unless the toolbar moved it.
    private var day: Date { shell.day }

    /// Whether the day on show is today.
    private var isToday: Bool { calendar.isDate(day, inSameDayAs: now) }

    /// The day's lectures, exams and deadlines, in order.
    private var dayEvents: [AgendaEvent] {
        agenda.events
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// The class in progress or next today, when the day on show is today.
    private var current: CurrentClass? {
        isToday ? CurrentClass.forAccessory(from: agenda.events, now: now) : nil
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if let current { NowCard(current: current, now: now) }
                    DayTimeline(events: dayEvents, day: day, now: isToday ? now : nil) { event in
                        shell.detail = .event(event)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    UpcomingCard()
                    NewsInCoursesCard()
                    CareerFiguresCard()
                }
                .frame(width: 360)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .background(LookBackground(style: look).ignoresSafeArea())
        .navigationTitle("Oggi")
        .navigationSubtitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Giorno precedente", systemImage: "chevron.left") { move(by: -1) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Oggi") { shell.day = .now }
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(isToday)
                Button("Giorno successivo", systemImage: "chevron.right") { move(by: 1) }
                    .keyboardShortcut("]", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Calendario", systemImage: "calendar") {
                    shell.route(to: .destination(.calendar))
                }
            }
        }
        #if DEBUG
        // `-OggiDayOffset 1` (or `-OggiDaysBack 1`) opens on another day, for trying the timeline on a weekday.
        .onAppear {
            // Backwards as its own key: a negative value reads as another flag.
            let offset = UserDefaults.standard.integer(forKey: "OggiDayOffset")
                - UserDefaults.standard.integer(forKey: "OggiDaysBack")
            guard offset != 0, !Self.appliedDayOffset else { return }
            Self.appliedDayOffset = true
            move(by: offset)
        }
        #endif
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 - Double(calendar.component(.second, from: .now))))
                now = .now
            }
        }
    }

    /// The greeting, the date in the look's wide type, and the day in one line.
    private var hero: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                if let name = session.student?.firstName {
                    Text("Buona giornata, \(name)!")
                        .font(.title3.weight(.semibold))
                }
                Text(heroDate)
                    .font(.system(size: 64, weight: .black).width(.expanded))
                    .kerning(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer()
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// "27.09 SAB".
    private var heroDate: String {
        let digits = day.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
            .replacingOccurrences(of: "/", with: ".")
        let weekday = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            .trimmingCharacters(in: .punctuationCharacters)
        return "\(digits) \(weekday)"
    }

    /// "3 lezioni · 1 scadenza".
    private var summary: String {
        let lectures = dayEvents.filter { $0.kind == .lecture }.count
        let exams = dayEvents.filter { $0.kind == .exam }.count
        let deadlines = dayEvents.filter { $0.kind == .deadline }.count
        var parts: [String] = []
        if lectures > 0 { parts.append(lectures == 1 ? "1 lezione" : "\(lectures) lezioni") }
        if exams > 0 { parts.append(exams == 1 ? "1 esame" : "\(exams) esami") }
        if deadlines > 0 { parts.append(deadlines == 1 ? "1 scadenza" : "\(deadlines) scadenze") }
        return parts.isEmpty ? String(localized: "Giornata libera") : parts.joined(separator: " · ")
    }

    /// Moves the day on show.
    private func move(by days: Int) {
        shell.day = calendar.date(byAdding: .day, value: days, to: day) ?? day
    }
}

// MARK: - Now

/// The class in progress, or the next one today, with a live countdown.
private struct NowCard: View {
    let current: CurrentClass
    let now: Date
    @Environment(\.shell) private var shell

    var body: some View {
        let event = current.event
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(current.isOngoing ? "Adesso" : "Prossima")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.9)
                Text(event.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                Text(detail(for: event))
                    .font(.body)
                    .opacity(0.92)
                if current.isOngoing {
                    ProgressView(value: current.progress(at: now))
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .padding(.top, 10)
                }
                HStack(spacing: 8) {
                    Button("Dettagli", systemImage: "info.circle") { shell.detail = .event(event) }
                    if event.roomLabel != nil {
                        Button("Mostra in Mappa", systemImage: "mappin.and.ellipse") {
                            shell.route(to: .destination(.map))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.22))
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: now...(current.isOngoing ? event.end : event.start), countsDown: true)
                    .font(.system(size: 44, weight: .black).width(.expanded).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                Text(current.isOngoing ? "alla fine" : "all'inizio")
                    .font(.callout)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(Color.accentColor.gradient, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func detail(for event: AgendaEvent) -> String {
        let hours = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        return [hours, event.roomLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Timeline

/// The day as a horizontal band from 8 to 19, lectures as blocks and deadlines as
/// marks, with a line at the current time.
private struct DayTimeline: View {
    let events: [AgendaEvent]
    let day: Date
    let now: Date?
    let open: (AgendaEvent) -> Void

    private let firstHour = 8
    private let lastHour = 19
    /// The widest a deadline's mark may be, so a long name stays inside the card.
    private static let deadlineWidth: CGFloat = 260
    private var calendar: Calendar { PoliMiDate.romeCalendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Orario").font(.headline)
            if events.isEmpty {
                ContentUnavailableView("Nessuna lezione", systemImage: "sun.max",
                                       description: Text("Niente in calendario per questo giorno."))
                    .frame(height: 150)
            } else {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .topLeading) {
                        hourGrid(width: width)
                        ForEach(events, id: \.id) { event in
                            block(for: event, width: width)
                        }
                        if let now, let x = position(of: now, width: width) {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 2, height: 128)
                                .offset(x: x - 1, y: 18)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }

    private func hourGrid(width: CGFloat) -> some View {
        ForEach(firstHour...lastHour, id: \.self) { hour in
            let x = CGFloat(hour - firstHour) / CGFloat(lastHour - firstHour) * width
            VStack(spacing: 4) {
                Text("\(hour)").font(.caption2).foregroundStyle(.secondary)
                Rectangle().fill(.separator).frame(width: 1, height: 128)
            }
            .offset(x: x - 4)
        }
    }

    @ViewBuilder
    private func block(for event: AgendaEvent, width: CGFloat) -> some View {
        if let start = position(of: event.start, width: width) {
            let end = position(of: event.end, width: width) ?? width
            let isNow = now.map { event.isOngoing(at: $0) } ?? false
            if event.kind == .deadline {
                Button { open(event) } label: {
                    Label(event.title, systemImage: "flag.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: Self.deadlineWidth, alignment: .leading)
                        .frame(height: 26)
                        .background(.background, in: .capsule)
                        .background(.orange.opacity(0.22), in: .capsule)
                }
                .buttonStyle(.plain)
                .help(event.title)
                .offset(x: min(max(start - 12, 0), width - Self.deadlineWidth), y: 118)
            } else {
                Button { open(event) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.callout.weight(.bold)).lineLimit(2)
                        Text(event.start.formatted(date: .omitted, time: .shortened)
                             + " – " + event.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                        Spacer(minLength: 0)
                        if let room = event.roomLabel { Text(room).font(.caption.weight(.semibold)) }
                    }
                    .padding(10)
                    .frame(width: max(end - start - 4, 44), height: 92, alignment: .topLeading)
                    .background(isNow ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary),
                                in: .rect(cornerRadius: 14))
                    // Opaque underneath, so the hour lines do not run through the block.
                    .background(.background, in: .rect(cornerRadius: 14))
                    .overlay {
                        if isNow { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2) }
                    }
                }
                .buttonStyle(.plain)
                .offset(x: start + 2, y: 22)
                .help(event.title)
            }
        }
    }

    /// Where a moment falls across the band, or `nil` outside the day shown.
    private func position(of date: Date, width: CGFloat) -> CGFloat? {
        guard calendar.isDate(date, inSameDayAs: day) else { return nil }
        let hours = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        let clamped = min(max(hours, Double(firstHour)), Double(lastHour))
        return CGFloat((clamped - Double(firstHour)) / Double(lastHour - firstHour)) * width
    }
}

// MARK: - Right column

/// The next deadlines and the next sitting.
private struct UpcomingCard: View {
    @Environment(UpdateFeed.self) private var feed
    @Environment(CareerModel.self) private var career
    @Environment(\.shell) private var shell

    var body: some View {
        MacCard("In arrivo") {
            let deadlines = feed.deadlines.filter { $0.due > .now }.sorted { $0.due < $1.due }.prefix(3)
            if deadlines.isEmpty && career.upcoming.isEmpty {
                Text("Nessuna scadenza in vista.").foregroundStyle(.secondary)
            }
            ForEach(Array(deadlines), id: \.id) { deadline in
                Button { shell.detail = .deadline(deadline) } label: {
                    MacRow(symbol: "flag", tint: .orange,
                           caption: "Scadenza · \(deadline.courseName)",
                           title: deadline.name,
                           detail: deadline.due.formatted(.relative(presentation: .named)))
                }
                .buttonStyle(.plain)
            }
            if let exam = career.upcoming.first {
                Button { shell.detail = .exam(exam) } label: {
                    MacRow(symbol: "doc.text", tint: .accentColor,
                           caption: ["Esame", exam.kind].compactMap { $0 }.joined(separator: " · "),
                           title: exam.courseName,
                           detail: exam.date.map { $0.formatted(.dateTime.day().month(.wide).hour().minute()) } ?? "Data da definire")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// What changed in the courses since the feed was last opened.
private struct NewsInCoursesCard: View {
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.shell) private var shell

    var body: some View {
        MacCard("Novità nei corsi", action: ("Tutte", { shell.route(to: .destination(.courses)) })) {
            let recent = feed.recent.prefix(4)
            if recent.isEmpty {
                Text("Nessuna novità.").foregroundStyle(.secondary)
            }
            ForEach(Array(recent), id: \.id) { update in
                MacRow(symbol: update.kind.symbol, tint: .accentColor,
                       caption: update.courseName,
                       title: update.title,
                       detail: update.detectedAt.formatted(.relative(presentation: .named)))
            }
        }
    }
}

/// The career's headline figures.
private struct CareerFiguresCard: View {
    @Environment(CareerModel.self) private var career
    @Environment(\.shell) private var shell

    var body: some View {
        MacCard("Carriera", action: ("Apri", { shell.route(to: .destination(.career)) })) {
            let plan = career.studyPlan
            HStack(alignment: .firstTextBaseline) {
                figure(career.weightedMean.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", "media")
                figure(plan.baseDegreeMark.map(String.init) ?? "—", "base di laurea")
                figure("\(plan.earnedCFU)", plan.totalCFU > 0 ? "CFU su \(plan.totalCFU)" : "CFU")
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.system(size: 24, weight: .black).width(.expanded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Building blocks

/// A titled card on the Oggi page.
struct MacCard<Content: View>: View {
    let title: LocalizedStringKey
    var action: (String, () -> Void)?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, action: (String, () -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let action {
                    Button(action.0, action: action.1).buttonStyle(.link)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }
}

/// One row of a card: a symbol, a caption, a title and a detail.
struct MacRow: View {
    let symbol: String
    let tint: Color
    let caption: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(title).font(.callout.weight(.semibold)).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

#Preview {
    NavigationStack { MacTodayView() }
        .previewEnvironment()
        .frame(width: 1200, height: 820)
}
#endif

import SwiftUI

/// One ``TodaySection`` of the Oggi page, drawn in its material, density and
/// colour, filled from the agenda, WeBeep and the career.
struct TodaySectionView: View {
    let section: TodaySection
    let style: TodayStyle
    let day: Date
    /// While arranging, one short row in place of the list: a page of compact
    /// tiles fits on screen, so a section can be carried past all the others.
    var collapsed = false
    /// Rows open their lesson or sitting: on the page, not in Personalizza,
    /// where a tap edits the section.
    var opensDetails = false

    @Environment(\.shell) private var shell
    @Environment(AgendaModel.self) private var agenda
    @Environment(UpdateFeed.self) private var updates
    @Environment(CareerModel.self) private var career
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme

    private var compact: Bool { section.density == .compact }

    /// The Flavor's accent for a tinted section's symbols, grey otherwise.
    private var accent: Color {
        section.tinted ? style.accent(scheme) : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Label(section.kind.title, systemImage: section.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(section.tinted ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
                .labelStyle(TitleOnlyUnlessTinted(tinted: section.tinted))
            card
        }
        // In the look's text design. Set here and on the greeting rather than
        // on the whole page, where it would restyle the date's system faces.
        .fontDesign(style.textDesign.design)
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        let entries = entries(now: .now)
        if section.kind.hasCourseColours && section.courseColours && !collapsed
            && section.form == .list && !entries.isEmpty {
            let lessons = TodayDigest.timetable(events: agenda.events, day: day)
            // Each lesson its own card in its course's colour.
            VStack(spacing: compact ? 6 : 8) {
                ForEach(lessons) { lesson in
                    lessonCard(lesson)
                }
            }
        } else if section.form == .tiles && !collapsed && !entries.isEmpty {
            // Tiles are cards of their own, as the small widgets are.
            tiles(entries)
        } else {
            materialCard
        }
    }

    private func lessonCard(_ lesson: AgendaEvent) -> some View {
        let colour = Theme.courseAccents[TodayDigest.colourIndex(for: lesson.title)]
        let shape = RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
        return opening(.event(lesson)) {
            HStack(spacing: 12) {
                Image(systemName: lesson.kind == .exam ? "pencil.and.list.clipboard" : "book.closed")
                    .font(compact ? .subheadline : .title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !compact {
                        Text([lesson.start.formatted(.dateTime.hour().minute().locale(locale)) + " – "
                              + lesson.end.formatted(.dateTime.hour().minute().locale(locale)),
                              lesson.room ?? lesson.roomAcronym].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if compact {
                    Text(lesson.start.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 9 : 13)
            .background {
                shape.fill(colour)
                    .visualEffect { content, proxy in
                        content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.5)))
                    }
            }
            .shadow(color: colour.opacity(0.3), radius: 8, y: 4)
            .accessibilityElement(children: .combine)
        }
    }

    /// A row as a button opening its detail, or as it is when it has none or
    /// the page is being edited.
    @ViewBuilder
    private func opening(_ detail: TodayDetail?, @ViewBuilder content: () -> some View) -> some View {
        if opensDetails, let detail {
            Button { shell.present { shell.detail = detail } } label: {
                content().contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private var materialCard: some View {
        let material = style.material(for: section)
        let padding: CGFloat = material.hasCard ? (compact ? 10 : 14) : 0
        return VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .todayMaterial(material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: compact ? 20 : 26)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        // Read once: two passes either side of a lesson's end would disagree.
        let entries = entries(now: .now)
        if collapsed {
            HStack(spacing: 12) {
                Image(systemName: section.kind.systemImage)
                    .foregroundStyle(accent)
                    .frame(width: 24)
                Text("Trascina per spostare")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
        } else if entries.isEmpty {
            empty(emptyText)
        } else {
            switch section.form {
            case .list: rows(entries)
            case .highlight: highlight(entries)
            case .rail: rail(entries)
            // Tiles are drawn by ``card``, which gives each its own surface.
            case .tiles: EmptyView()
            }
        }
    }

    /// What this section lists, in one shape the forms can all draw.
    private func entries(now: Date) -> [TodayEntry] {
        switch section.kind {
        case .currentClass:
            guard let current = CurrentClass.forAccessory(from: agenda.events, now: now) else { return [] }
            let when = current.isOngoing
                ? String(localized: "fino alle \(current.event.end.formatted(.dateTime.hour().minute().locale(locale)))")
                : current.event.start.formatted(.dateTime.hour().minute().locale(locale))
            return [TodayEntry(id: "current-\(current.event.id)",
                               symbol: current.event.kind == .exam ? "pencil.and.list.clipboard" : "person.bubble",
                               title: current.event.title,
                               detail: [current.isOngoing ? String(localized: "Adesso") : String(localized: "Prossima"),
                                        current.event.room ?? current.event.roomAcronym].compactMap { $0 }.joined(separator: " · "),
                               when: when, date: current.event.start, opens: .event(current.event))]
        case .upcoming:
            return TodayDigest.upcoming(events: agenda.events, deadlines: updates.deadlines, exams: career.sessions,
                                        now: now, limit: section.itemLimit)
                .map { item in
                    TodayEntry(id: item.id, symbol: item.source == .exam ? "graduationcap" : "pencil.and.list.clipboard",
                               title: item.title, detail: item.detail,
                               when: item.date.formatted(.relative(presentation: .named).locale(locale)),
                               date: item.date, opens: item.opens)
                }
        case .timetable:
            return TodayDigest.timetable(events: agenda.events, day: day).map { event in
                TodayEntry(id: "event-\(event.id)", symbol: event.kind == .exam ? "pencil.and.list.clipboard" : "clock",
                           title: event.title, detail: event.room ?? event.roomAcronym,
                           when: event.start.formatted(.dateTime.hour().minute().locale(locale)),
                           date: event.start, opens: .event(event))
            }
        case .deadlines:
            return TodayDigest.deadlines(updates.deadlines, now: now, limit: section.itemLimit).map { deadline in
                TodayEntry(id: "deadline-\(deadline.id)", symbol: "pencil.and.list.clipboard",
                           title: deadline.name, detail: deadline.courseName,
                           when: deadline.due.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
                           date: deadline.due, opens: nil)
            }
        case .exams:
            return TodayDigest.exams(career.sessions, now: now, limit: section.itemLimit).map { session in
                TodayEntry(id: "exam-\(session.id)", symbol: "graduationcap",
                           title: session.courseName, detail: session.room,
                           when: session.date?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? "",
                           date: session.date, opens: .exam(session))
            }
        }
    }

    private var emptyText: LocalizedStringKey {
        switch section.kind {
        case .currentClass: "Nessuna lezione oggi"
        case .upcoming: "Niente in arrivo"
        case .timetable: "Nessuna lezione"
        case .deadlines: "Nessuna scadenza"
        case .exams: "Nessun esame in programma"
        }
    }

    // MARK: - Forms

    /// One row per entry: the shape every section had before forms.
    private func rows(_ entries: [TodayEntry]) -> some View {
        ForEach(entries) { entry in
            row(symbol: entry.symbol, title: entry.title, detail: entry.detail,
                trailing: entry.when, last: entry.id == entries.last?.id, opens: entry.opens)
        }
    }

    /// The first entry large — the answer to "what have I got next" — and the
    /// rest as thin rows under a rule.
    @ViewBuilder
    private func highlight(_ entries: [TodayEntry]) -> some View {
        if let lead = entries.first {
            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                opening(lead.opens) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: lead.symbol)
                            .font(compact ? .subheadline : .body)
                            .foregroundStyle(accent)
                            .frame(width: 24)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lead.when.localizedCapitalized)
                                .font(.system(size: compact ? 22 : 27, weight: .bold, design: style.textDesign.design))
                                .foregroundStyle(style.accent(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(lead.title)
                                .font(.headline)
                                .lineLimit(2)
                            if let detail = lead.detail, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                if entries.count > 1 {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(entries.dropFirst()) { entry in
                            opening(entry.opens) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(entry.id == entries.dropFirst().first?.id ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                                        .frame(width: 6, height: 6)
                                    Text(entry.title).font(.subheadline).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(entry.when)
                                        .font(.caption.weight(.medium))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, compact ? 5 : 7)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, compact ? 4 : 6)
        }
    }

    /// Two columns of small cards, as the small widgets are.
    private func tiles(_ entries: [TodayEntry]) -> some View {
        let material = style.material(for: section)
        let corner: CGFloat = compact ? 18 : 22
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(entries) { entry in
                opening(entry.opens) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Image(systemName: entry.symbol)
                                .font(.subheadline)
                                .foregroundStyle(accent)
                            Spacer(minLength: 6)
                            Text(entry.when)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(section.tinted ? AnyShapeStyle(style.accent(scheme)) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary.opacity(0.5), in: .capsule)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.footnote.weight(.semibold)).lineLimit(2)
                            if let detail = entry.detail, !detail.isEmpty {
                                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(compact ? 10 : 13)
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity, minHeight: compact ? 88 : 104, alignment: .topLeading)
                    .todayMaterial(material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: corner)
                }
            }
        }
    }

    /// A rail down the left, so when a thing happens reads without the rows.
    ///
    /// Entries all on the day being shown — the timetable, always — carry the
    /// hour there instead of the date: the date is the page's already.
    private func rail(_ entries: [TodayEntry]) -> some View {
        let calendar = PoliMiDate.romeCalendar
        let sameDay = entries.allSatisfy { entry in
            guard let date = entry.date else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }
        return VStack(spacing: 0) {
            ForEach(entries) { entry in
                let isLast = entry.id == entries.last?.id
                opening(entry.opens) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 1) {
                            if sameDay {
                                Text(entry.date?.formatted(.dateTime.hour().minute().locale(locale)) ?? "—")
                                    .font(.footnote.weight(.bold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            } else {
                                Text(entry.date?.formatted(.dateTime.day().locale(locale)) ?? "—")
                                    .font(.footnote.weight(.bold))
                                    .monospacedDigit()
                                Text((entry.date?.formatted(.dateTime.month(.abbreviated).locale(locale)) ?? "").uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: sameDay ? 44 : 34)
                        VStack(spacing: 0) {
                            Circle()
                                .fill(entry.id == entries.first?.id ? AnyShapeStyle(style.accent(scheme)) : AnyShapeStyle(.clear))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.tertiary, lineWidth: entry.id == entries.first?.id ? 0 : 2))
                                .padding(.top, 3)
                            if !isLast {
                                Rectangle().fill(.quaternary).frame(width: 2)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            // The rail already says when: the row says where.
                            Text([sameDay ? nil : entry.when, entry.detail]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.bottom, isLast ? 0 : (compact ? 12 : 16))
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
    }

    private func row(symbol: String, title: String, detail: String?, trailing: String, last: Bool,
                     opens: TodayDetail? = nil) -> some View {
        opening(opens) {
            rowContent(symbol: symbol, title: title, detail: detail, trailing: trailing, last: last)
        }
    }

    private func rowContent(symbol: String, title: String, detail: String?, trailing: String, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(accent)
                    .frame(width: 24)
                if compact {
                    Text(title).font(.subheadline).lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                        if let detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, compact ? 7 : 10)
            if !last {
                Divider().padding(.leading, 36)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, compact ? 8 : 14)
    }
}

/// The section title is plain text; a tinted section shows its symbol too.
private struct TitleOnlyUnlessTinted: LabelStyle {
    let tinted: Bool

    func makeBody(configuration: Configuration) -> some View {
        if tinted {
            HStack(spacing: 6) { configuration.icon; configuration.title }
        } else {
            configuration.title
        }
    }
}

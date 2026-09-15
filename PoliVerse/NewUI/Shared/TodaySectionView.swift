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

    @Environment(AgendaService.self) private var agenda
    @Environment(UpdateFeed.self) private var updates
    @Environment(CareerService.self) private var career
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

    private var card: some View {
        let material = style.material(for: section)
        let padding: CGFloat = material.hasCard ? (compact ? 10 : 14) : 0
        return VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .todayMaterial(material, flavor: style.flavor, cornerRadius: compact ? 20 : 26)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let now = Date.now
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
        } else {
            list(now: now)
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        switch section.kind {
        case .currentClass:
            if let current = CurrentClass.forAccessory(from: agenda.events, now: now) {
                row(symbol: current.event.kind == .exam ? "pencil.and.list.clipboard" : "person.bubble",
                    title: current.event.title,
                    detail: [current.isOngoing ? String(localized: "Adesso") : String(localized: "Prossima"),
                             current.event.room ?? current.event.roomAcronym].compactMap { $0 }.joined(separator: " · "),
                    trailing: current.isOngoing
                        ? String(localized: "fino alle \(current.event.end.formatted(.dateTime.hour().minute().locale(locale)))")
                        : current.event.start.formatted(.dateTime.hour().minute().locale(locale)),
                    last: true)
            } else {
                empty("Nessuna lezione oggi")
            }
        case .upcoming:
            let items = TodayDigest.upcoming(events: agenda.events, deadlines: updates.deadlines, exams: career.sessions,
                                             now: now, limit: section.itemLimit)
            if items.isEmpty {
                empty("Niente in arrivo")
            } else {
                ForEach(items) { item in
                    row(symbol: item.source == .exam ? "graduationcap" : "pencil.and.list.clipboard",
                        title: item.title, detail: item.detail,
                        trailing: item.date.formatted(.relative(presentation: .named).locale(locale)),
                        last: item.id == items.last?.id)
                }
            }
        case .timetable:
            let events = TodayDigest.timetable(events: agenda.events, day: day)
            if events.isEmpty {
                empty("Nessuna lezione")
            } else {
                ForEach(events) { event in
                    row(symbol: event.kind == .exam ? "pencil.and.list.clipboard" : "clock",
                        title: event.title, detail: event.room ?? event.roomAcronym,
                        trailing: event.start.formatted(.dateTime.hour().minute().locale(locale)),
                        last: event.id == events.last?.id)
                }
            }
        case .deadlines:
            let deadlines = TodayDigest.deadlines(updates.deadlines, now: now, limit: section.itemLimit)
            if deadlines.isEmpty {
                empty("Nessuna scadenza")
            } else {
                ForEach(deadlines) { deadline in
                    row(symbol: "pencil.and.list.clipboard", title: deadline.name, detail: deadline.courseName,
                        trailing: deadline.due.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
                        last: deadline.id == deadlines.last?.id)
                }
            }
        case .exams:
            let sessions = TodayDigest.exams(career.sessions, now: now, limit: section.itemLimit)
            if sessions.isEmpty {
                empty("Nessun esame in programma")
            } else {
                ForEach(sessions) { session in
                    row(symbol: "graduationcap", title: session.courseName, detail: session.room,
                        trailing: session.date?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? "",
                        last: session.id == sessions.last?.id)
                }
            }
        }
    }

    private func row(symbol: String, title: String, detail: String?, trailing: String, last: Bool) -> some View {
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

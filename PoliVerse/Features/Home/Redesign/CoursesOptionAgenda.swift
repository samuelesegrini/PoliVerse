import SwiftUI

/// **Opzione A — Agenda.** Corsi ordinati dal tempo, non dall'alfabeto.
///
/// La domanda con cui si apre Corsi quasi sempre è "dove devo andare adesso e
/// dopo": qui la pagina risponde a quella e basta. In cima la lezione in corso
/// o la prossima, a tutta larghezza; sotto una linea del tempo con gli orari a
/// sinistra e i corsi come fermate; in fondo, piccoli, i corsi che questa
/// settimana non hanno lezione — che restano raggiungibili senza occupare il
/// posto migliore della pagina.
struct CoursesOptionAgenda: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale

    private var scheduled: [CourseBrief] {
        courses.filter { $0.nextLecture != nil }
            .sorted { ($0.nextLecture ?? .distantFuture) < ($1.nextLecture ?? .distantFuture) }
    }

    private var idle: [CourseBrief] { courses.filter { $0.nextLecture == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let lead = scheduled.first {
                headline(lead)
            }
            if scheduled.count > 1 {
                section("In arrivo") {
                    VStack(spacing: 0) {
                        ForEach(Array(scheduled.dropFirst())) { brief in
                            stop(brief, last: brief.id == scheduled.last?.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .lookCard()
                }
            }
            if !idle.isEmpty {
                section("Senza lezioni in vista") {
                    FlowRow(spacing: 8) {
                        ForEach(idle) { brief in
                            Button { open(brief.course) } label: { pill(brief) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - La lezione che conta adesso

    private func headline(_ brief: CourseBrief) -> some View {
        Button { open(brief.course) } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if brief.isOngoing {
                        Circle().fill(.white).frame(width: 7, height: 7)
                        Text("In corso").font(.caption.weight(.bold))
                    } else {
                        Text(brief.isToday ? "Prossima oggi" : "Prossima lezione")
                            .font(.caption.weight(.bold))
                    }
                    Spacer()
                    UnreadDot(count: brief.unread, tint: .white.opacity(0.28))
                }
                .textCase(.uppercase)

                Text(brief.course.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if let start = brief.nextLecture {
                        Label(start.formatted(.dateTime.hour().minute().locale(locale)), systemImage: "clock")
                            .monospacedDigit()
                    }
                    if let room = brief.room {
                        Label(room, systemImage: "mappin.and.ellipse")
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(brief.accent.gradient, in: .rect(cornerRadius: Theme.cardCorner, style: .continuous))
            .shadow(color: brief.accent.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Le fermate della linea

    private func stop(_ brief: CourseBrief, last: Bool) -> some View {
        Button { open(brief.course) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(brief.nextLecture?.formatted(.dateTime.hour().minute().locale(locale)) ?? "—")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)

                // La linea con il punto: è lei a far leggere l'elenco come un
                // orario invece che come una lista.
                VStack(spacing: 0) {
                    Circle().fill(brief.accent).frame(width: 9, height: 9).padding(.top, 5)
                    if !last {
                        Rectangle().fill(.quaternary).frame(width: 1.5)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(brief.course.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        UnreadDot(count: brief.unread)
                    }
                    Text([brief.whenDay(locale: locale), brief.room].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, last ? 0 : 16)
            }
            .padding(.horizontal, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func pill(_ brief: CourseBrief) -> some View {
        HStack(spacing: 8) {
            CourseGlyph(course: brief.course, size: 24, circular: true)
            Text(brief.course.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            UnreadDot(count: brief.unread)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .lookCard(cornerRadius: 20)
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }
}

private extension CourseBrief {
    /// "Oggi", "Domani", "Mercoledì" — la parte di giorno, senza l'ora, che
    /// nella linea del tempo sta già a sinistra.
    func whenDay(locale: Locale) -> String? {
        guard let start = nextLecture else { return nil }
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(start) { return String(localized: "Oggi") }
        if calendar.isDateInTomorrow(start) { return String(localized: "Domani") }
        return start.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized
    }
}

/// Elementi che vanno a capo quando la riga finisce.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview("A · Agenda") {
    ScrollView {
        CoursesOptionAgenda(courses: CourseBrief.samples)
            .padding(20)
    }
    .previewEnvironment()
}

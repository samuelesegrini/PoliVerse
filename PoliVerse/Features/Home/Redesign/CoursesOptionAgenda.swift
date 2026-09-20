import SwiftUI

/// **Opzione A — Agenda.** Corsi ordinati dal tempo, non dall'alfabeto.
///
/// La domanda con cui si apre Corsi quasi sempre è "dove devo andare adesso e
/// dopo": qui la pagina risponde a quella e basta. In cima la lezione in corso
/// o la prossima, sulla stessa carta colorata con cui Oggi disegna la lezione
/// del momento; sotto una linea del tempo con gli orari a sinistra e i corsi
/// come fermate; in fondo, piccoli, i corsi che questa settimana non hanno
/// lezione — che restano raggiungibili senza occupare il posto migliore.
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
        VStack(alignment: .leading, spacing: 24) {
            if let lead = scheduled.first {
                headline(lead)
            }
            if scheduled.count > 1 {
                section("In arrivo") {
                    VStack(spacing: 0) {
                        ForEach(Array(scheduled.dropFirst())) { brief in
                            Button { open(brief.course) } label: {
                                stop(brief, last: brief.id == scheduled.last?.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .lookCard()
                }
            }
            if !idle.isEmpty {
                section("Senza lezioni in vista") { pills }
            }
        }
    }

    // MARK: - La lezione che conta adesso

    private func headline(_ brief: CourseBrief) -> some View {
        Button { open(brief.course) } label: {
            CourseAccentCard(colour: brief.accent) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        if brief.isOngoing {
                            Circle().fill(Theme.onAccent).frame(width: 6, height: 6)
                        }
                        Text(brief.isOngoing ? "Adesso" : brief.isToday ? "Prossima oggi" : "Prossima lezione")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                        Spacer(minLength: 8)
                        CourseBadge(count: brief.unread, onColour: true)
                    }

                    Text(brief.course.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        if let start = brief.nextLecture {
                            Label {
                                if brief.isOngoing {
                                    Text("fino alle \(brief.nextLectureEnd?.formatted(.dateTime.hour().minute().locale(locale)) ?? "—")")
                                } else {
                                    Text(start.formatted(.dateTime.hour().minute().locale(locale)))
                                }
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .monospacedDigit()
                        }
                        if let room = brief.room {
                            Label(room, systemImage: "mappin.and.ellipse")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.medium))
                    .opacity(0.9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Le fermate della linea

    private func stop(_ brief: CourseBrief, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(brief.nextLecture?.formatted(.dateTime.hour().minute().locale(locale)) ?? "—")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
                .padding(.top, 1)

            // La linea con il punto: è lei a far leggere l'elenco come un
            // orario invece che come una lista.
            VStack(spacing: 0) {
                Circle().fill(brief.accent).frame(width: 9, height: 9).padding(.top, 5)
                if !last {
                    Rectangle().fill(.quaternary).frame(width: 1.5)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(brief.course.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    CourseBadge(count: brief.unread)
                }
                Text([brief.dayText(locale: locale), brief.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, last ? 0 : 16)
        }
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// I corsi fermi, in fila come i filtri della pagina: piccoli, di lato,
    /// raggiungibili.
    private var pills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(idle) { brief in
                    Button { open(brief.course) } label: {
                        HStack(spacing: 8) {
                            CourseMonogram(course: brief.course, size: 24)
                            Text(brief.course.name)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            CourseBadge(count: brief.unread)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, brief.unread > 0 ? 6 : 12)
                        .padding(.vertical, 6)
                        .lookCard(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }
}

#Preview("A · Agenda") {
    CoursesOptionPreview { CoursesOptionAgenda(courses: CourseBrief.samples) }
}

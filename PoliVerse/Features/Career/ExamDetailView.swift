import SwiftUI

/// Everything known about one exam sitting.
struct ExamDetailView: View {
    let exam: ExamSession

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    /// Captured when the button is tapped, so the sheet keeps its event even
    /// if the sitting's start passes while it is open.
    @State private var calendarDraft: ExamCalendarEvent?

    /// Only for a sitting still ahead: past ones have no use in a calendar.
    private var calendarEvent: ExamCalendarEvent? {
        guard (exam.date ?? .distantPast) > .now else { return nil }
        return ExamCalendarEvent(sitting: exam)
    }

    private var accent: Color {
        switch exam.status {
        case .graded(let grade): grade.passed ? .green : .red
        case .enrolled: Theme.brand
        case .open: .orange
        case .notYetOpen, .closed: .secondary
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let grade = exam.grade {
                        section("Esito") {
                            row("Voto", grade.display, icon: "rosette")
                            row("Superato", grade.passed ? "Sì" : "No",
                                icon: grade.passed ? "checkmark.seal" : "xmark.seal")
                            if grade.refusable {
                                // Worth stating plainly: the window to refuse a
                                // mark is short and easy to miss.
                                Label("Puoi ancora rifiutare questo voto dai servizi online.",
                                      systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }

                    section("Appello") {
                        if let date = exam.date {
                            row("Data",
                                date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)).capitalized,
                                icon: "calendar")
                            row("Ora", date.formatted(.dateTime.hour().minute().locale(locale)),
                                icon: "clock")
                        }
                        if let room = exam.room { row("Aula", room, icon: "mappin.and.ellipse") }
                        if let kind = exam.kind, !kind.isEmpty {
                            row("Tipo", kind, icon: "doc.text")
                        }
                        if let teacher = exam.teacher { row("Docente", teacher, icon: "person") }
                        row("Codice", exam.courseCode, icon: "number")
                    }

                    ExamTimelineSection(exam: exam)

                    if exam.grade == nil {
                        section("Iscrizione") {
                            row("Stato", exam.status.label, icon: "checkmark.circle")
                            if let opens = exam.enrolmentOpens {
                                row("Apertura",
                                    opens.formatted(.dateTime.day().month(.wide).year().locale(locale)),
                                    icon: "calendar.badge.plus")
                            }
                            if let closes = exam.enrolmentCloses {
                                row("Chiusura",
                                    closes.formatted(.dateTime.day().month(.wide).year().locale(locale)),
                                    icon: "calendar.badge.minus")
                            }
                            if let count = exam.enrolledCount, count > 0 {
                                row("Iscritti", "\(count)", icon: "person.3")
                            }
                        }

                        // Enrolment is a write against the real university
                        // system. Doing it from here untested could sign someone
                        // up for an exam by accident, so the app points at the
                        // official services instead of guessing at the API.
                        Label(
                            "Le iscrizioni agli appelli si gestiscono dai Servizi Online del Politecnico.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(item: $calendarDraft) { AddToCalendarSheet(event: $0).ignoresSafeArea() }
            .navigationTitle("Dettaglio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                if calendarEvent != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            calendarDraft = calendarEvent
                        } label: {
                            Label("Aggiungi al calendario", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exam.courseName)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)

            Text(exam.status.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(0.15), in: .capsule)
                .foregroundStyle(accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) { content() }
        }
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }
}

// MARK: - Previews

#Preview("Appello") {
    ExamDetailView(exam: MockData.examSessions()[0]).previewInNavigation()
}

import SwiftUI

/// Everything the agenda knows about one entry.
///
/// Worth a screen of its own because a lecture row can only show the time and
/// a room code, while the payload carries the full room name, the teaching
/// form, and whatever the agenda attached as description or tags.
struct EventDetailView: View {
    let event: AgendaEvent

    @Environment(LiveActivityController.self) private var liveActivity
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    private var accent: Color {
        switch event.kind {
        case .lecture: Theme.brand
        case .exam: .red
        case .deadline: .orange
        case .news: .blue
        case .custom: .purple
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if LiveActivityController.canStart(event) {
                        liveActivityButton
                    }

                    section("Quando") {
                        row("Data",
                            event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)).capitalized,
                            icon: "calendar")
                        // A deadline is an instant; showing "23:59 – 23:59"
                        // would read as a mistake.
                        if event.duration > 0 {
                            row("Orario",
                                "\(event.start.formatted(.dateTime.hour().minute().locale(locale))) – \(event.end.formatted(.dateTime.hour().minute().locale(locale)))",
                                icon: "clock")
                            row("Durata", durationText, icon: "hourglass")
                        } else {
                            row("Ora", event.start.formatted(.dateTime.hour().minute().locale(locale)),
                                icon: "clock")
                        }
                    }

                    if event.room != nil || event.roomAcronym != nil {
                        section("Dove") {
                            if let room = event.room {
                                row("Aula", room, icon: "mappin.and.ellipse")
                            }
                            if let acronym = event.roomAcronym, acronym != event.room {
                                row("Codice", acronym, icon: "number")
                            }
                        }
                    }

                    if event.calendarName?.isEmpty == false || event.subtype?.isEmpty == false {
                        section("Corso") {
                            if let calendar = event.calendarName, !calendar.isEmpty {
                                row("Calendario", calendar, icon: "books.vertical")
                            }
                            if let subtype = event.subtype, !subtype.isEmpty {
                                row("Tipo", subtype, icon: "person.bubble")
                            }
                        }
                    }

                    if let details = event.details, !details.isEmpty {
                        section("Dettagli") {
                            Text(details)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardBackground()
                        }
                    }

                    if !event.tags.isEmpty {
                        section("Etichette") {
                            FlowTags(tags: event.tags, accent: accent)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dettaglio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    /// Offered rather than automatic: a Live Activity nobody asked for is
    /// something on your Lock Screen you have to dismiss.
    @ViewBuilder
    private var liveActivityButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            if liveActivity.isShowing(event) {
                Button(role: .destructive) {
                    liveActivity.end()
                } label: {
                    Label("Togli dalla schermata di blocco", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    liveActivity.start(for: event)
                } label: {
                    Label("Sto andando a lezione", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
            } else if !liveActivity.isShowing(event) {
                Text("Conto alla rovescia e aula sulla schermata di blocco, fino a fine lezione.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var durationText: String {
        let minutes = Int(event.duration / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label(event.kind.label, systemImage: event.kind.icon)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.15), in: .capsule)
                    .foregroundStyle(accent)

                if event.isOngoing() {
                    Text("In corso")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent, in: .capsule)
                        .foregroundStyle(Theme.onAccent)
                }
            }
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
            Text(label).font(.subheadline).foregroundStyle(.secondary)
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

/// Tags wrap onto as many lines as they need.
private struct FlowTags: View {
    let tags: [String]
    let accent: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(0.15), in: .capsule)
                .foregroundStyle(accent)
        }
    }
}

// MARK: - Previews

#Preview("Lezione") {
    EventDetailView(event: MockData.agendaEvents(around: .now)[0])
        .previewInNavigation()
}

#Preview("Componente · Tag") {
    FlowTags(tags: ["Lezione", "Informatica", "Aula 3.0.1", "Bovisa"],
             accent: Theme.brand)
        .padding()
        .previewEnvironment()
}

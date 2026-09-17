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

                    factsPanel

                    if LiveActivityController.canStart(event) {
                        liveActivityButton
                    }

                    if let details = event.details, !details.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            LookHeading("Dettagli")
                            Text(details)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lookCard()
                        }
                        .padding(.top, 8)
                    }

                    if !event.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            LookHeading("Etichette")
                            FlowTags(tags: event.tags, accent: accent)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .courseScreen()
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The header names the event: the bar only closes the sheet.
                ToolbarItem(placement: .principal) { Text(verbatim: "") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    /// When, where and what, side by side on one glass panel, as the exam
    /// page lays out a sitting.
    private var factsPanel: some View {
        let facts: [(label: String, value: String)] = [
            (String(localized: "Data"), event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)).capitalized),
            event.duration > 0
                ? (String(localized: "Orario"), "\(event.start.formatted(.dateTime.hour().minute().locale(locale))) – \(event.end.formatted(.dateTime.hour().minute().locale(locale)))")
                : (String(localized: "Ora"), event.start.formatted(.dateTime.hour().minute().locale(locale))),
            event.duration > 0 ? (String(localized: "Durata"), durationText) : nil,
            event.room.map { (String(localized: "Aula"), $0) },
            event.roomAcronym.flatMap { $0 != event.room ? (String(localized: "Codice"), $0) : nil },
            event.subtype.flatMap { $0.isEmpty ? nil : (String(localized: "Tipo"), $0) },
            event.calendarName.flatMap { $0.isEmpty ? nil : (String(localized: "Calendario"), $0) },
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label(event.kind.label, systemImage: event.kind.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                if event.isOngoing() {
                    Label("In corso", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.tint(accent.opacity(0.25)), in: .capsule)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .topLeading)],
                      alignment: .leading, spacing: 14) {
                ForEach(facts, id: \.label) { fact in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fact.label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(fact.value).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
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
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Button {
                    liveActivity.start(for: event)
                } label: {
                    Label("Sto andando a lezione", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
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

    /// The subject as a glass tile in the middle, then the title and when.
    private var header: some View {
        VStack(spacing: 10) {
            PageHero(symbol: event.kind == .lecture || event.kind == .exam
                        ? SubjectSymbol.symbol(for: event.title) : event.kind.icon,
                     title: Text(event.title),
                     summary: Text(event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized))
        }
        .frame(maxWidth: .infinity)
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
                .foregroundStyle(accent)
                .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - Previews

#Preview("Lezione") {
    EventDetailView(event: AgendaEvent.samples(around: .now)[0])
        .previewInNavigation()
}

#Preview("Componente · Tag") {
    FlowTags(tags: ["Lezione", "Informatica", "Aula 3.0.1", "Bovisa"],
             accent: Theme.brand)
        .padding()
        .previewEnvironment()
}

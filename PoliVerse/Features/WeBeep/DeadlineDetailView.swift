import SwiftUI

/// Everything the app knows about one WeBeep assignment deadline.
///
/// The Scadenze rows on Oggi were the only ones that opened nothing: the row
/// shows a name and a day, while the deadline also carries the course it
/// belongs to and the exact hour it falls at, which is what decides whether
/// tonight is still enough time.
struct DeadlineDetailView: View {
    /// The deadline being shown.
    let deadline: AssignmentDeadline

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// Opens WeBeep in the browser.
    @Environment(\.openURL) private var openURL
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss

    /// Whether the system's event editor is up.
    @State private var addingToCalendar = false

    /// The colour a deadline is drawn in, the same orange the agenda uses for one.
    private var accent: Color { .orange }

    /// The view's content.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    factsPanel
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(verbatim: deadline.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The header names the deadline: the bar only closes the sheet.
                ToolbarItem(placement: .principal) { Text(verbatim: "") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(isPresented: $addingToCalendar) {
                AddToCalendarSheet(event: ExamCalendarEvent(deadline: deadline))
            }
        }
    }

    /// The subject tile, the assignment's name, and the course it belongs to.
    private var header: some View {
        PageHero(symbol: "doc.badge.clock",
                 title: Text(verbatim: deadline.name),
                 summary: Text(verbatim: deadline.courseName))
            .frame(maxWidth: .infinity)
    }

    /// When it is due and how long is left, on one glass panel, as the event
    /// and exam pages lay out their facts.
    private var factsPanel: some View {
        let facts: [(label: String, value: String)] = [
            (String(localized: "Consegna"),
             deadline.due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)).capitalized),
            (String(localized: "Ora"), deadline.due.formatted(.dateTime.hour().minute().locale(locale))),
            (String(localized: "Corso"), deadline.courseName),
            (String(localized: "Codice"), deadline.courseCode),
        ]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Scadenza", systemImage: "doc.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                if let left = timeLeft {
                    Text(left)
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

    /// Opening the assignment on WeBeep, and saving the deadline to the calendar.
    ///
    /// Whether the student has already handed in is not in what Moodle answers
    /// here, so the page never claims either way and sends them to WeBeep to see.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openURL(Self.weBeepURL(for: deadline))
            } label: {
                Label("Apri su WeBeep", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button {
                addingToCalendar = true
            } label: {
                Label("Aggiungi al Calendario", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Text("La consegna si fa su WeBeep. Qui non si vede se hai già consegnato.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// How long is left, in days or hours, or nothing once the deadline has passed.
    private var timeLeft: String? {
        let seconds = deadline.due.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let hours = Int(seconds / 3600)
        if hours >= 48 { return String(localized: "fra \(hours / 24) giorni") }
        if hours >= 1 { return String(localized: "fra \(hours) h") }
        return String(localized: "fra \(max(1, Int(seconds / 60))) min")
    }

    /// The assignment's page on WeBeep.
    ///
    /// Moodle's `mod/assign/view.php` takes either a course-module id as `id` or
    /// the assignment's own instance id as `a`. Only the latter is known here,
    /// so the link goes through `a`. The site is the one the WeBeep session
    /// itself is against (``WeBeepAuth/siteURL``).
    ///
    /// - Parameter deadline: The deadline to link to.
    /// - Returns: The URL.
    static func weBeepURL(for deadline: AssignmentDeadline) -> URL {
        URL(string: "\(WeBeepAuth.siteURL)/mod/assign/view.php?a=\(deadline.id)")!
    }
}

// MARK: - Previews

#Preview("Scadenza") {
    DeadlineDetailView(deadline: AssignmentDeadline(
        id: 41_233, courseCode: "054412", courseName: "Analisi Matematica II",
        name: "Consegna 3 — serie di Fourier", due: .now.addingTimeInterval(36 * 3600)))
        .previewEnvironment()
}

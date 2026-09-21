import SwiftUI
import UserNotifications

/// Which reminders to send, and how far ahead.
///
/// Built on the same principles as ``DataStorageView`` and
/// ``ConnectionsView``, so the settings pages read as one kind of page:
///
/// 1. **A picture first.** A bell in front in clear glass, the kinds of
///    reminder behind it in tinted glass, and one badge that says whether
///    reminders are going out at all.
/// 2. **One sentence** under it: what the badge means, or which reminder comes
///    next — the proof that the settings below are doing something.
/// 3. **The rows**, grouped by the question they answer — *what*, *when*,
///    *not when* — each kind with its icon and a line saying when it arrives,
///    so a toggle is never a bare word the reader has to interpret.
struct NotificationSettingsView: View {
    @Environment(NotificationModel.self) private var notifications
    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    @State private var showsAllScheduled = false

    var body: some View {
        @Bindable var notifications = notifications
        let ramp = FlavorRamp(style: style, scheme: scheme)
        let colours = Dictionary(uniqueKeysWithValues: zip(ReminderKind.allCases, ramp.colours(ReminderKind.allCases.count)))
        let health = health

        List {
            Section {
                VStack(spacing: 18) {
                    HeroTileStack(
                        tiles: [HeroTile(id: "bell", symbol: "bell", colour: ramp.colour(at: 0))]
                            + [ReminderKind.lecture, .deadline, .exam].map {
                                HeroTile(id: $0.rawValue, symbol: $0.symbol, colour: colours[$0] ?? ramp.neutral)
                            },
                        placeholder: HeroTile(id: "empty", symbol: "bell", colour: ramp.neutral),
                        badge: health.badge(accent: style.accent(scheme)),
                        mode: ramp.mode)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
                        Text(health.title)
                            .font(.title2.weight(.bold))
                        Text(health.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: health)

                    switch notifications.authorization {
                    case .notDetermined:
                        Button {
                            Task {
                                await notifications.requestAuthorization()
                                await reschedule()
                            }
                        } label: {
                            Text("Attiva i promemoria").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    case .denied:
                        // Asking again does nothing: the system remembers a
                        // refusal, so the only route left is Settings.
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Text("Apri Impostazioni").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    default:
                        EmptyView()
                    }
                }
                .listRowInsets(EdgeInsets(top: 20, leading: 24, bottom: 16, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .lookRow()

            if isAuthorised {
                remindersSection(colours: colours, neutral: ramp.neutral)
                updatesSection(colour: colours[.update] ?? ramp.neutral)
                quietSection
                mutedSection
                resultsFileSection
                scheduledSection(colours: colours, neutral: ramp.neutral)
            }
        }
        .lookList()
        .navigationTitle("Promemoria")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.3), value: notifications.preferences)
        .task {
            await notifications.refreshAuthorization()
            await reschedule()
        }
        // Any change to what or how far ahead reschedules the lot.
        .onChange(of: notifications.preferences) { _, _ in
            Task { await reschedule() }
        }
    }

    private var isAuthorised: Bool {
        switch notifications.authorization {
        case .notDetermined, .denied: false
        default: true
        }
    }

    // MARK: - Sections

    private func remindersSection(colours: [ReminderKind: Flavor.RGB], neutral: Flavor.RGB) -> some View {
        @Bindable var notifications = notifications
        let preferences = notifications.preferences
        return Section {
            KindToggle(kind: .lecture, colour: colours[.lecture] ?? neutral,
                       detail: preferences.lectures
                           ? String(localized: "\(leadDescription(preferences.leadMinutes)) prima dell’inizio")
                           : String(localized: "Spento"),
                       isOn: $notifications.preferences.lectures)
            if preferences.lectures {
                Picker("Quanto prima", selection: $notifications.preferences.leadMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(leadDescription(minutes)).tag(minutes)
                    }
                }
            }
            KindToggle(kind: .deadline, colour: colours[.deadline] ?? neutral,
                       detail: dayBeforeDetail(preferences.deadlines),
                       isOn: $notifications.preferences.deadlines)
            KindToggle(kind: .exam, colour: colours[.exam] ?? neutral,
                       detail: dayBeforeDetail(preferences.exams),
                       isOn: $notifications.preferences.exams)
            KindToggle(kind: .enrolment, colour: colours[.enrolment] ?? neutral,
                       detail: dayBeforeDetail(preferences.enrolments),
                       isOn: $notifications.preferences.enrolments)
        } header: {
            Text("Promemoria")
        } footer: {
            Text("Calcolati dal tuo orario e programmati sul dispositivo, senza inviare nulla. Scadenze, esami e iscrizioni arrivano il giorno prima, quando c’è ancora tempo per agire.")
        }
    }

    private func updatesSection(colour: Flavor.RGB) -> some View {
        @Bindable var notifications = notifications
        let enabled = notifications.preferences.examUpdates
        return Section {
            KindToggle(kind: .update, colour: colour,
                       detail: enabled
                           ? String(localized: "Esiti, aule, appelli spostati")
                           : String(localized: "Restano visibili nell’app"),
                       isOn: $notifications.preferences.examUpdates)
            if enabled {
                ForEach(UpdateCategory.allCases) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { notifications.preferences.isEnabled(category) },
                        set: { notifications.preferences.setCategory(category, enabled: $0) }))
                }
                Toggle(isOn: $notifications.preferences.weBeepUpdates) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Anche da WeBeep")
                        Text("File, annunci e consegne dei corsi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                hourPicker("Riepilogo giornaliero alle", selection: $notifications.preferences.digestHour)
            }
        } header: {
            Text("Novità")
        } footer: {
            Text(enabled
                 ? "Ciò che conta — un esito, un’aula, un appello spostato — arriva subito; il resto nel riepilogo. Un tipo spento non notifica ma resta visibile nell’app."
                 : "Le novità restano nell’app, senza notifiche.")
        }
    }

    private var quietSection: some View {
        @Bindable var notifications = notifications
        let preferences = notifications.preferences
        return Section {
            hourPicker("Dalle", selection: $notifications.preferences.quietFrom)
            hourPicker("Alle", selection: $notifications.preferences.quietUntil)
        } header: {
            Text("Silenzio notturno")
        } footer: {
            Text(preferences.quietFrom == preferences.quietUntil
                 ? "Stessa ora di inizio e fine: nessun silenzio."
                 : "In queste ore arriva solo ciò che è urgente, come un esito o un appello spostato; il resto aspetta la mattina.")
        }
    }

    @ViewBuilder
    private var mutedSection: some View {
        if !notifications.preferences.mutedCourses.isEmpty {
            Section {
                ForEach(notifications.preferences.mutedCourses, id: \.self) { course in
                    Label(course.name, systemImage: "speaker.slash")
                }
                .onDelete { notifications.preferences.mutedCourses.remove(atOffsets: $0) }
            } header: {
                Text("Corsi silenziati")
            } footer: {
                Text("Nessuna notifica, promemoria o riepilogo; le novità restano nell’app. Scorri per riattivarli.")
            }
            .lookRow()
        }
    }

    @ViewBuilder
    private var resultsFileSection: some View {
        @Bindable var notifications = notifications
        if notifications.preferences.examUpdates {
            Section {
                Toggle(isOn: $notifications.preferences.readResultsFiles) {
                    Label("Cerca la mia matricola negli esiti", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Privacy")
            } footer: {
                // Said plainly: the file lists other students.
                Text("Quando un docente pubblica un file di esiti su WeBeep, l’app lo apre sul telefono e cerca solo la tua matricola. Tiene soltanto il tuo voto, che non appare nelle notifiche; i dati degli altri non vengono salvati né inviati. Funziona con PDF testuali e CSV.")
            }
            .lookRow()
        }
    }

    private func scheduledSection(colours: [ReminderKind: Flavor.RGB], neutral: Flavor.RGB) -> some View {
        let scheduled = notifications.scheduled
        let shown = showsAllScheduled ? scheduled : Array(scheduled.prefix(5))
        return Section {
            if scheduled.isEmpty {
                Text("Nessun promemoria in arrivo.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shown) { item in
                    let kind = ReminderKind(item.kind)
                    HStack(spacing: 12) {
                        GlassTile(symbol: kind.symbol, colour: colours[kind] ?? neutral, side: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .lineLimit(2)
                            Text(item.fireDate.formatted(
                                .dateTime.weekday(.wide).day().month(.abbreviated).hour().minute().locale(locale)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.fireDate, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                if scheduled.count > 5 {
                    Button(showsAllScheduled ? "Mostra meno" : "Mostra tutti (\(scheduled.count))") {
                        withAnimation(.snappy) { showsAllScheduled.toggle() }
                    }
                }
            }
        } header: {
            Text("In arrivo")
        } footer: {
            // Worth saying: the cap is Apple's, not a choice, and it explains
            // why a reminder three weeks out never arrives.
            Text("iOS tiene al massimo \(NotificationPlan.limit) promemoria in attesa: vengono programmati i più vicini, gli altri man mano.")
        }
    }

    // MARK: - Helpers

    private func dayBeforeDetail(_ isOn: Bool) -> String {
        isOn ? String(localized: "Il giorno prima alle 18:00") : String(localized: "Spento")
    }

    private func leadDescription(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private func hourPicker(_ title: LocalizedStringKey, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                // In the reader's own clock style, on Rome's hours.
                Text(PoliMiDate.time(hour, on: .now).formatted(.dateTime.hour().minute().locale(locale)))
                    .tag(hour)
            }
        }
    }

    private func reschedule() async {
        await notifications.reschedule(
            events: agenda.events, exams: career.sessions, assignments: feed.deadlines, updates: feed.updates)
    }

    // MARK: - The one piece of news

    private enum Health: Equatable {
        case notAsked, denied, allOff, nothingScheduled, next(title: String, date: Date)

        func badge(accent: Color) -> HeroBadge {
            switch self {
            // A plus, as on ConnectionsView: the fix is to add something.
            case .notAsked: HeroBadge(symbol: "plus", tint: accent)
            case .denied: HeroBadge(symbol: "xmark", tint: .orange)
            case .allOff: HeroBadge(symbol: "moon.fill", tint: .gray)
            case .nothingScheduled, .next: HeroBadge(symbol: "checkmark", tint: .green)
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .notAsked: "Promemoria spenti"
            case .denied: "Promemoria non consentiti"
            case .allOff: "Tutto in silenzio"
            case .nothingScheduled, .next: "Promemoria attivi"
            }
        }

        var detail: LocalizedStringResource {
            switch self {
            case .notAsked: "Lezioni, scadenze ed esami, un attimo prima che servano. Tutto resta sul dispositivo."
            case .denied: "Le notifiche di PoliVerse sono disattivate in Impostazioni."
            case .allOff: "Hai spento ogni tipo di promemoria e di novità."
            case .nothingScheduled: "Per ora non c’è niente in arrivo."
            case .next(let title, let date):
                "Il prossimo: \(title), \(date.formatted(.relative(presentation: .named)))."
            }
        }
    }

    private var health: Health {
        switch notifications.authorization {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        default: break
        }
        let preferences = notifications.preferences
        if !preferences.lectures, !preferences.deadlines, !preferences.exams,
           !preferences.enrolments, !preferences.examUpdates {
            return .allOff
        }
        guard let next = notifications.scheduled.min(by: { $0.fireDate < $1.fireDate }) else {
            return .nothingScheduled
        }
        return .next(title: next.title, date: next.fireDate)
    }
}

// MARK: - Rows

/// The kinds of reminder, each with the icon it wears in the picture, its
/// toggle and the scheduled list.
private enum ReminderKind: String, CaseIterable {
    case lecture, deadline, exam, enrolment, update

    init(_ kind: PlannedNotification.Kind) {
        switch kind {
        case .lecture: self = .lecture
        case .deadline: self = .deadline
        case .exam: self = .exam
        case .enrolment: self = .enrolment
        case .update: self = .update
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .lecture: "Lezioni"
        case .deadline: "Scadenze"
        case .exam: "Esami"
        case .enrolment: "Chiusura iscrizioni"
        case .update: "Novità sugli esami"
        }
    }

    var symbol: String {
        switch self {
        case .lecture: "calendar"
        case .deadline: "checklist"
        case .exam: "graduationcap"
        case .enrolment: "person.crop.circle.badge.clock"
        case .update: "sparkles"
        }
    }
}

/// A kind as a toggle: its tile, its name, and when it arrives.
private struct KindToggle: View {
    let kind: ReminderKind
    let colour: Flavor.RGB
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                GlassTile(symbol: kind.symbol, colour: colour, side: 30)
                    .saturation(isOn ? 1 : 0)
                    .opacity(isOn ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Promemoria") {
    NotificationSettingsView().previewInNavigation()
}

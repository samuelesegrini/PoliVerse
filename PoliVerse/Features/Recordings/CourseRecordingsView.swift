import SwiftUI

/// The recorded lectures of one course, from the recman archive, grouped by
/// academic year: one card per year, newest first.
///
/// A tap plays the recording in the system player, from the stream Webex serves;
/// when Webex will not say where that is, the recording opens on Webex in the
/// browser. See `docs/recordings.md`.
struct CourseRecordingsView: View {
    /// The course whose recordings these are.
    let course: Course

    /// The shared ``RecordingsModel``, from the environment.
    @Environment(RecordingsModel.self) private var model
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``WeBeepModel``, from the environment, for the course's link into
    /// recman.
    @Environment(WeBeepModel.self) private var weBeep
    /// Opens a recording's Webex page in the browser.
    @Environment(\.openURL) private var openURL
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The look in use, which the page's materials come from.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Whether the sign-in sheet is up.
    @State private var showingSignIn = false
    /// The recording being looked up on recman, for its row's spinner.
    @State private var opening: Recording.ID?
    /// Set when a recording could not be opened.
    @State private var openFailed = false
    /// A recording waiting for the student to sign in to Webex.
    @State private var webexSignIn: WebexSignIn?
    /// Recordings whose Webex sign-in went through in this visit, so a look-up that
    /// stops on a sign-in again opens the browser rather than asking once more.
    @State private var webexSignedIn: Set<Recording.ID> = []
    /// A recording waiting for the student to confirm the email Webex wants.
    @State private var emailFor: Recording?
    /// The email being typed.
    @State private var emailDraft = ""
    /// A recording waiting for the student to read Webex's notice before it plays.
    @State private var pendingPlay: PendingPlay?
    /// Whether the notice before a recording has been read once.
    @AppStorage("recordingsNoticeRead") private var noticeRead = false

    /// The course's recordings, newest first.
    private var recordings: [Recording] { model.recordings(for: course) }

    /// The recordings by academic year, the latest year first.
    private var years: [(year: String, recordings: [Recording])] {
        Dictionary(grouping: recordings, by: \.academicYear)
            .map { ($0.key, $0.value) }
            .sorted { $0.year > $1.year }
    }

    /// The view's content.
    var body: some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !recordings.isEmpty {
                    CoursePageHero(
                        tiles: [HeroTile(id: "recordings", symbol: "play.rectangle", colour: ramp.main)],
                        placeholder: HeroTile(id: "empty", symbol: "play.rectangle", colour: ramp.main),
                        title: Text("Registrazioni"), summary: summary, badge: nil, mode: ramp.mode)
                }

                switch model.phase {
                case .needsSignIn:
                    signInCard
                case .unavailable(let message):
                    unavailableCard(message)
                case .idle, .loading:
                    EmptyView()
                }

                if session.useMockData {
                    Label("Dati di esempio: disattivali per leggere l'archivio reale.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                ForEach(years, id: \.year) { group in
                    yearCard(group.year, group.recordings, colour: ramp.main)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if recordings.isEmpty {
                if model.phase == .loading {
                    ProgressView()
                } else if model.phase == .idle {
                    ContentUnavailableView("Nessuna registrazione", systemImage: "play.rectangle",
                                           description: Text("L'archivio non ha registrazioni di questo corso."))
                }
            }
        }
        .sheet(isPresented: $showingSignIn) {
            RecordingsSignInSheet { await model.load(course, force: true, entry: entry) }
        }
        .sheet(item: $webexSignIn) { pending in
            WebexSignInSheet(address: pending.address) {
                webexSignedIn.insert(pending.recording.id)
                Task { await open(pending.recording) }
            }
        }
        .alert("Email per Webex", isPresented: Binding(
            get: { emailFor != nil }, set: { if !$0 { emailFor = nil } })) {
            TextField("nome.cognome@mail.polimi.it", text: $emailDraft)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Continua") {
                let trimmed = emailDraft.trimmingCharacters(in: .whitespaces)
                model.webexEmail = trimmed.isEmpty ? nil : trimmed
                if let recording = emailFor { Task { await open(recording) } }
                emailFor = nil
            }
            Button("Annulla", role: .cancel) { emailFor = nil }
        } message: {
            Text("Webex chiede l'email del tuo account del Politecnico prima di passare all'accesso. Te la chiediamo una volta sola.")
        }
        .alert("Registrazione della lezione", isPresented: Binding(
            get: { pendingPlay != nil }, set: { if !$0 { pendingPlay = nil } })) {
            Button("Guarda") {
                noticeRead = true
                if let pending = pendingPlay { pending.play() }
                pendingPlay = nil
            }
            Button("Annulla", role: .cancel) { pendingPlay = nil }
        } message: {
            Text("La registrazione può contenere le voci e le immagini di altri partecipanti. È per il tuo studio: non va registrata né diffusa.")
        }
        .alert("Registrazione non disponibile", isPresented: $openFailed) {
            Button("Apri l'archivio") { openURL(RecordingsWebKit.entry) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Non è stato possibile trovare il collegamento a Webex. Puoi cercarla nell'archivio dal browser.")
        }
        .task { await model.load(course, entry: entry) }
        .refreshable { await model.load(course, force: true, entry: entry) }
    }

    /// The course's "Registrazioni" link on WeBeep, the way into its recordings.
    private func entry() async -> URL? {
        await weBeep.recordingsEntry(for: course)
    }

    /// "12 registrazioni · 24 h".
    private var summary: Text? {
        guard !recordings.isEmpty else { return nil }
        let minutes = recordings.compactMap(\.minutes).reduce(0, +)
        let hours = Int((Double(minutes) / 60).rounded())
        return minutes > 0
            ? Text("\(recordings.count) registrazioni · \(hours) h")
            : Text("\(recordings.count) registrazioni")
    }

    /// Asks for the Politecnico's sign-in, which recman needs on a session of its own.
    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Accedi all'archivio", systemImage: "play.rectangle.on.rectangle")
                .font(.headline)
            Text("Le registrazioni stanno sui Servizi Online, che vogliono un accesso del browser, distinto da quello dell'app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Accedi") { showingSignIn = true }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent(for: course))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .lookCard()
    }

    /// Says recman could not be read, with the way out to the browser.
    private func unavailableCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Button("Apri l'archivio nel browser") { openURL(RecordingsWebKit.entry) }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .lookCard()
    }

    /// One academic year's recordings on one card.
    private func yearCard(_ year: String, _ recordings: [Recording], colour: Flavor.RGB) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(verbatim: year) {
                Text("\(recordings.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(recordings) { recording in
                    RecordingRow(recording: recording, colour: colour, isOpening: opening == recording.id,
                                 last: recording.id == recordings.last?.id) {
                        Task { await open(recording) }
                    }
                }
            }
            .padding(.horizontal, style.material.hasCard ? 14 : 0)
            .padding(.vertical, style.material.hasCard ? 4 : 0)
            .lookCard()
        }
    }

    /// Finds the recording's Webex page and opens it in the browser.
    private func open(_ recording: Recording) async {
        guard opening == nil else { return }
        opening = recording.id
        defer { opening = nil }
        if let address = await model.webexAddress(for: recording) {
            let (outcome, cookies) = await model.stream(at: address, accountEmail: session.student?.email)
            switch outcome {
            case .stream(let stream) where stream.hlsURL != nil:
                let pending = PendingPlay(stream: stream, recording: recording, cookies: cookies)
                if stream.needsDisclaimer, !noticeRead { pendingPlay = pending } else { pending.play() }
            case .signInNeeded where model.webexEmail == nil:
                // Webex refused the institutional email, or there was none: ask
                // which one the account uses.
                emailDraft = session.student?.email ?? ""
                emailFor = recording
            case .signInNeeded where !webexSignedIn.contains(recording.id):
                // The email did not get through either: Webex's own page, once.
                webexSignIn = WebexSignIn(recording: recording, address: address)
            default:
                // Webex would not say where it streams: its own page still plays it.
                openURL(address)
            }
        } else if model.phase == .needsSignIn {
            showingSignIn = true
        } else if !session.useMockData {
            openFailed = true
        }
    }
}

/// One recording: when, what it covered, and how long.
private struct RecordingRow: View {
    /// The recording this row shows.
    let recording: Recording
    /// The course's colour.
    let colour: Flavor.RGB
    /// Whether the recording is being looked up.
    let isOpening: Bool
    /// The last row of its card draws no hairline under it.
    var last = false
    /// Opens the recording.
    let onTap: () -> Void

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CourseRowTile(symbol: recording.form == .lecture ? "play.rectangle" : "play.rectangle.on.rectangle",
                                  colour: colour)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.topic ?? recording.form.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if isOpening {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                if !last {
                    Divider().padding(.leading, 42)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Riproduce la registrazione")
    }

    /// "Lun 21 set, 13:34 · 135 min", with the kind when the topic took the title's place.
    private var details: String {
        var parts = [recording.recordedAt.formatted(
            .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(locale))]
        if let minutes = recording.minutes { parts.append(String(localized: "\(minutes) min")) }
        if recording.topic != nil, recording.form != .lecture { parts.append(recording.form.title) }
        return parts.joined(separator: " · ")
    }
}

/// A recording ready to play once the notice has been read.
private struct PendingPlay {
    /// What Webex answered.
    let stream: WebexStream
    /// The recording.
    let recording: Recording
    /// Webex's cookies, sent with the media requests.
    let cookies: [HTTPCookie]

    /// Starts it in the system player.
    @MainActor
    func play() {
        RecordingPlayer.shared.play(stream, recording: recording, cookies: cookies)
    }
}

/// A recording whose Webex page wants the student to sign in to Webex.
private struct WebexSignIn: Identifiable {
    /// The recording to play once signed in.
    let recording: Recording
    /// Its Webex address, where the sign-in starts.
    let address: URL
    /// The recording's identity.
    var id: Int { recording.id }
}

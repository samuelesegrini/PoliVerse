import SwiftUI

/// The recorded lectures of one course, from the recman archive.
///
/// The page is the course's own edition: a card to pick up the recording left
/// half-watched, what is left to watch, and the year's recordings by month, which
/// a filter narrows to those still to watch or saved offline. The same teaching's
/// recordings from other years are kept apart under "Altre edizioni", closed until
/// asked for, since a course is one year's edition but a student resitting it still
/// wants last year's lectures.
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
    /// The shared ``RecordingDownloads``, from the environment.
    @Environment(RecordingDownloads.self) private var downloads
    /// The shared ``WeBeepModel``, from the environment, for the course's link into
    /// recman.
    @Environment(WeBeepModel.self) private var weBeep
    /// Opens a recording's Webex page in the browser.
    @Environment(\.openURL) private var openURL
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The look in use, which the page's materials come from.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Which recordings the list shows.
    @State private var filter = Filter.all
    /// The other editions the student opened, or closed when open by default.
    @State private var toggledEditions: Set<String> = []
    /// Whether the sign-in sheet is up.
    @State private var showingSignIn = false
    /// The recording being looked up on recman, for its row's spinner.
    @State private var opening: Recording.ID?
    /// Set when a recording could not be opened.
    @State private var openFailed = false
    /// Why a download could not start, when one could not.
    @State private var downloadRefusal: String?
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

    /// Which recordings the list shows.
    private enum Filter: Hashable, CaseIterable {
        case all, toWatch, offline

        /// The filter's name in the picker.
        var title: LocalizedStringKey {
            switch self {
            case .all: "Tutte"
            case .toWatch: "Da vedere"
            case .offline: "Offline"
            }
        }

        /// What the list says when nothing passes the filter.
        var emptyMessage: LocalizedStringKey {
            switch self {
            case .all: "Nessuna registrazione."
            case .toWatch: "Hai visto tutte le registrazioni."
            case .offline: "Nessuna registrazione salvata sul dispositivo."
            }
        }
    }

    /// The course's recordings, every year's, newest first.
    private var recordings: [Recording] { model.recordings(for: course) }

    /// The recordings of the course's own edition, newest first.
    private var edition: [Recording] { recordings.filter { $0.isOf(edition: course) } }

    /// The same teaching's recordings from other years, the latest year first.
    private var otherEditions: [(year: String, recordings: [Recording])] {
        Dictionary(grouping: recordings.filter { !$0.isOf(edition: course) }, by: \.academicYear)
            .map { ($0.key, $0.value) }
            .sorted { $0.year > $1.year }
    }

    /// The recording to pick up again: the one last played and left part-way.
    private var resumable: (recording: Recording, progress: RecordingProgress)? {
        recordings
            .compactMap { recording in
                model.progress[recording.transferID].flatMap { $0.resumeAt != nil ? (recording, $0) : nil }
            }
            .max { $0.1.updatedAt < $1.1.updatedAt }
    }

    /// Whether a recording passes the filter.
    private func passes(_ recording: Recording) -> Bool {
        switch filter {
        case .all: true
        case .toWatch: model.progress[recording.transferID]?.completed != true
        case .offline: downloads.file(for: recording) != nil
        }
    }

    /// Whether an other edition's recordings are showing: the latest one opens by
    /// itself when the course's own edition has none.
    private func isOpen(_ year: String) -> Bool {
        let byDefault = edition.isEmpty && year == otherEditions.first?.year
        return byDefault != toggledEditions.contains(year)
    }

    /// The view's content.
    var body: some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header

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

                if !recordings.isEmpty {
                    VStack(spacing: 14) {
                        if let resumable {
                            continueCard(resumable.recording, progress: resumable.progress, colour: ramp.main)
                        }
                        if !edition.isEmpty { stats }
                    }

                    Picker("Mostra", selection: $filter.animation()) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let shown = edition.filter(passes)
                    if !edition.isEmpty, shown.isEmpty {
                        Text(filter.emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(months(of: shown, withYear: false), id: \.title) { month in
                        monthCard(month.title, month.recordings, colour: ramp.main)
                    }

                    if !otherEditions.isEmpty {
                        otherEditionsCard
                        ForEach(otherEditions.filter { isOpen($0.year) }, id: \.year) { group in
                            ForEach(months(of: group.recordings.filter(passes), withYear: true), id: \.title) { month in
                                monthCard(month.title, month.recordings, colour: ramp.main)
                            }
                        }
                    }
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
        .alert("Download non disponibile", isPresented: Binding(
            get: { downloadRefusal != nil }, set: { if !$0 { downloadRefusal = nil } })) {
            Button("OK", role: .cancel) { downloadRefusal = nil }
        } message: {
            Text(downloadRefusal ?? "")
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

    // MARK: - Header

    /// "Registrazioni", and how many the edition has.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Registrazioni")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if !edition.isEmpty {
                Text("\(edition.count) registrazioni · \(course.academicYear)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
    }

    /// The seconds of the edition still to watch: what is left of each recording
    /// not watched yet.
    private var secondsToWatch: Double {
        edition.reduce(0.0) { total, recording in
            let progress = model.progress[recording.transferID]
            guard progress?.completed != true else { return total }
            let length = Double(recording.minutes ?? 0) * 60
            return total + max(length - (progress?.position ?? 0), 0)
        }
    }

    /// Three counts side by side: to watch, the time that takes, and saved offline.
    private var stats: some View {
        let seconds = secondsToWatch
        let left = seconds >= 3600
            ? Text("\(Int((seconds / 3600).rounded())) h")
            : Text("\(Int((seconds / 60).rounded())) min")
        return HStack(spacing: 10) {
            statTile(Text("\(model.toWatch(in: course))"), label: "da vedere")
            statTile(left, label: "rimaste")
            statTile(Text("\(downloads.savedCount(in: recordings))"), label: "offline")
        }
    }

    /// One count, large, over what it counts.
    private func statTile(_ value: Text, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .lookCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    /// The recording left part-way, on a card of glass tinted with the course's
    /// colour, with the button that picks it up where it stopped.
    private func continueCard(_ recording: Recording, progress: RecordingProgress, colour: Flavor.RGB) -> some View {
        let resumeAt = progress.resumeAt ?? 0
        let timestamp = Duration.seconds(resumeAt)
            .formatted(.time(pattern: resumeAt >= 3600 ? .hourMinuteSecond : .minuteSecond))
        var details = [recording.recordedAt.formatted(
            .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))]
        if progress.duration > 0 {
            details.append(String(localized: "mancano \(Int(((progress.duration - progress.position) / 60).rounded())) min"))
        }
        if !recording.isOf(edition: course) { details.append(recording.academicYear) }
        let download = downloads.status(of: recording)

        return GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continua a guardare")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(colour.color)
                    Text(recording.topic ?? recording.form.title)
                        .font(.title3.bold())
                        .lineLimit(3)
                    Text(details.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                ProgressView(value: progress.fraction)
                    .tint(colour.color)
                    .accessibilityLabel("Vista al \(Int((progress.fraction * 100).rounded()))%")
                HStack(spacing: 10) {
                    Button {
                        Task { await open(recording) }
                    } label: {
                        HStack(spacing: 8) {
                            if opening == recording.id {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Riprendi da \(timestamp)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(colour.color)
                    continueDownload(recording, download, colour: colour)
                }
            }
            .padding(18)
            .glassEffect(.regular.tint(colour.color.opacity(0.22)), in: .rect(cornerRadius: 26))
        }
    }

    /// The continue card's round download button, while the recording can still be
    /// saved or is being saved.
    @ViewBuilder
    private func continueDownload(_ recording: Recording, _ status: RecordingDownloads.Status, colour: Flavor.RGB) -> some View {
        switch status {
        case .downloading(let fraction):
            ProgressView(value: fraction ?? 0)
                .progressViewStyle(.circular)
                .tint(colour.color)
                .frame(width: 50, height: 50)
                .glassEffect(.regular, in: .circle)
                .accessibilityLabel("Download in corso")
        case .idle, .failed:
            if !model.downloadForbidden.contains(recording.transferID), !session.useMockData {
                Button {
                    Task { await download(recording) }
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.headline)
                        .foregroundStyle(colour.color)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(recording.megabytes.map { String(localized: "Scarica per vederla offline (\($0) MB)") }
                                    ?? String(localized: "Scarica per vederla offline"))
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Sign-in and errors

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

    // MARK: - The list

    /// Recordings by the month they were made in, the latest first, titled
    /// "Settembre", or "Settembre 2025" for another edition's.
    private func months(of recordings: [Recording], withYear: Bool) -> [(title: String, recordings: [Recording])] {
        let calendar = Calendar.current
        return Dictionary(grouping: recordings) { calendar.dateInterval(of: .month, for: $0.recordedAt)?.start ?? $0.recordedAt }
            .sorted { $0.key > $1.key }
            .map { month, recordings in
                let format = withYear
                    ? Date.FormatStyle().month(.wide).year().locale(locale)
                    : Date.FormatStyle().month(.wide).locale(locale)
                return (month.formatted(format).capitalized(with: locale), recordings)
            }
    }

    /// One month's recordings on one card.
    private func monthCard(_ title: String, _ recordings: [Recording], colour: Flavor.RGB) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(verbatim: title) {
                Text("\(recordings.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(recordings) { recording in
                    let progress = model.progress[recording.transferID]
                    let download = downloads.status(of: recording)
                    RecordingRow(recording: recording, progress: progress, download: download, colour: colour,
                                 isOpening: opening == recording.id,
                                 last: recording.id == recordings.last?.id) {
                        Task { await open(recording) }
                    }
                    .contextMenu {
                        if progress?.completed == true {
                            Button("Segna come da vedere", systemImage: "circle") {
                                model.setWatched(false, recording)
                            }
                        } else {
                            Button("Segna come vista", systemImage: "checkmark.circle") {
                                model.setWatched(true, recording)
                            }
                        }
                        downloadMenu(recording, download)
                    }
                }
            }
            .padding(.horizontal, style.material.hasCard ? 14 : 0)
            .padding(.vertical, style.material.hasCard ? 4 : 0)
            .lookCard()
        }
    }

    /// The same teaching's other years, one row each, which opens that year's
    /// recordings under the card.
    private var otherEditionsCard: some View {
        let groups = otherEditions
        return VStack(alignment: .leading, spacing: 10) {
            LookHeading("Altre edizioni")
            VStack(spacing: 0) {
                ForEach(groups, id: \.year) { group in
                    let open = isOpen(group.year)
                    Button {
                        withAnimation {
                            if toggledEditions.contains(group.year) { toggledEditions.remove(group.year) }
                            else { toggledEditions.insert(group.year) }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            HStack {
                                Text(verbatim: group.recordings.first?.academicYear ?? group.year)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Text("\(group.recordings.filter(passes).count)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(open ? 90 : 0))
                            }
                            .frame(minHeight: 50)
                            if group.year != groups.last?.year {
                                Divider()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(open ? Text("Aperta") : Text("Chiusa"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .lookCard()
            Text("Le registrazioni dello stesso insegnamento negli anni precedenti, dall'archivio.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    /// The download entries of a row's menu, for what the recording's state allows.
    @ViewBuilder
    private func downloadMenu(_ recording: Recording, _ status: RecordingDownloads.Status) -> some View {
        switch status {
        case .downloaded:
            Button("Rimuovi il download", systemImage: "trash", role: .destructive) { downloads.delete(recording) }
        case .downloading:
            Button("Annulla il download", systemImage: "xmark.circle") { downloads.cancel(recording) }
        case .interrupted:
            Button("Riprendi il download", systemImage: "arrow.down.circle") {
                if !downloads.resume(recording) { Task { await download(recording) } }
            }
            Button("Annulla il download", systemImage: "xmark.circle") { downloads.delete(recording) }
        case .idle, .failed:
            if !model.downloadForbidden.contains(recording.transferID), !session.useMockData {
                Button(recording.megabytes.map { String(localized: "Scarica per vederla offline (\($0) MB)") }
                       ?? String(localized: "Scarica per vederla offline"),
                       systemImage: "arrow.down.circle") {
                    Task { await download(recording) }
                }
            }
        }
    }

    /// Asks Webex for the recording's file and downloads it, when the lecturer allows.
    private func download(_ recording: Recording) async {
        guard opening == nil else { return }
        opening = recording.id
        defer { opening = nil }
        guard let address = await model.webexAddress(for: recording) else {
            downloadRefusal = String(localized: "Non è stato possibile raggiungere la registrazione su Webex.")
            return
        }
        let (outcome, cookies) = await model.stream(at: address, accountEmail: session.student?.email, for: recording)
        switch outcome {
        case .stream(let stream) where stream.allowsDownload:
            downloads.download(recording, from: stream, cookies: cookies)
        case .stream:
            downloadRefusal = String(localized: "Il docente non permette di scaricare questa registrazione. Si può guardare in streaming.")
        default:
            downloadRefusal = String(localized: "Webex non ha risposto. Apri la registrazione una volta, poi riprova a scaricarla.")
        }
    }

    /// Plays the recording: from the device when it is saved there, and otherwise from
    /// Webex, finding its stream first.
    private func open(_ recording: Recording) async {
        guard opening == nil else { return }
        if let file = downloads.file(for: recording) {
            let model = model
            RecordingPlayer.shared.play(
                file, recording: recording, duration: Double(recording.minutes ?? 0) * 60,
                startAt: model.progress[recording.transferID]?.resumeAt
            ) { position, duration, final in
                model.played(to: position, of: duration, in: recording, final: final)
            }
            return
        }
        opening = recording.id
        defer { opening = nil }
        if let address = await model.webexAddress(for: recording) {
            let (outcome, cookies) = await model.stream(at: address, accountEmail: session.student?.email, for: recording)
            switch outcome {
            case .stream(let stream) where stream.hlsURL != nil:
                let pending = PendingPlay(stream: stream, recording: recording, cookies: cookies,
                                          startAt: model.progress[recording.transferID]?.resumeAt, model: model)
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

/// One recording: the day it was made on a tile, what it covered, and where the
/// student stands with it.
private struct RecordingRow: View {
    /// The recording this row shows.
    let recording: Recording
    /// How far the student has got with it.
    let progress: RecordingProgress?
    /// Where its download stands.
    let download: RecordingDownloads.Status
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
    /// The date tile's width, scaled with the reader's text.
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 44

    /// Whether the recording has been watched, which greys the row.
    private var watched: Bool { progress?.completed == true }

    /// The view's content.
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    dateTile
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.topic ?? recording.form.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(watched ? .secondary : .primary)
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    state
                        .frame(minWidth: 24)
                }
                .padding(.vertical, 10)
                if !last {
                    Divider().padding(.leading, tile + 12)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(progress?.resumeAt != nil ? "Riprende la registrazione" : "Riproduce la registrazione")
    }

    /// The weekday over the day of the month, in the course's colour until watched.
    private var dateTile: some View {
        VStack(spacing: 0) {
            Text(recording.recordedAt.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
            Text(recording.recordedAt.formatted(.dateTime.day().locale(locale)))
                .font(.title3.bold())
                .monospacedDigit()
        }
        .foregroundStyle(watched ? AnyShapeStyle(.secondary) : AnyShapeStyle(colour.color))
        .frame(width: tile, height: tile * 1.1)
        .background(watched ? AnyShapeStyle(.quaternary) : AnyShapeStyle(colour.color.opacity(0.14)),
                    in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    /// Where the student stands with the recording, at the row's end.
    @ViewBuilder
    private var state: some View {
        if isOpening {
            ProgressView().controlSize(.small)
        } else if case .downloading(let fraction) = download {
            ProgressView(value: fraction ?? 0)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(colour.color)
                .accessibilityLabel("Download in corso")
        } else if watched {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Vista")
        } else if let progress, progress.fraction > 0.01 {
            ProgressRing(fraction: progress.fraction, colour: colour.color)
                .accessibilityLabel("Vista al \(Int((progress.fraction * 100).rounded()))%")
        } else if case .downloaded = download {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Disponibile offline")
        } else {
            Circle()
                .fill(colour.color)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Da vedere")
        }
    }

    /// "13:34 · 135 min", or "· mancano 52 min" once started, with the kind when the
    /// topic took the title's place and where its download stands.
    private var details: String {
        var parts = [recording.recordedAt.formatted(.dateTime.hour().minute().locale(locale))]
        if let progress, !progress.completed, progress.resumeAt != nil, progress.duration > 0 {
            let left = Int(((progress.duration - progress.position) / 60).rounded())
            parts.append(String(localized: "mancano \(left) min"))
        } else if let minutes = recording.minutes {
            parts.append(String(localized: "\(minutes) min"))
        }
        if recording.topic != nil, recording.form != .lecture { parts.append(recording.form.title) }
        switch download {
        case .downloaded: parts.append(String(localized: "offline"))
        case .failed: parts.append(String(localized: "download non riuscito"))
        case .interrupted: parts.append(String(localized: "download interrotto"))
        case .idle, .downloading: break
        }
        return parts.joined(separator: " · ")
    }
}

/// How much of a recording has been played, as a ring.
private struct ProgressRing: View {
    /// The share played, from 0 to 1.
    let fraction: Double
    /// The ring's colour.
    let colour: Color
    /// The ring's side, scaled with the reader's text.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    /// The view's content.
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side, height: side)
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
    /// Where the student stopped last time, to start from.
    let startAt: Double?
    /// Where the position is kept.
    let model: RecordingsModel

    /// Starts it in the system player, from where the student stopped.
    @MainActor
    func play() {
        let recording = recording, model = model
        RecordingPlayer.shared.play(stream, recording: recording, cookies: cookies, startAt: startAt) { position, duration, final in
            model.played(to: position, of: duration, in: recording, final: final)
        }
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

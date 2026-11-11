import SwiftUI

// The pieces every screen draws a loading section with, so that waiting, failing,
// being empty and arriving look and behave the same everywhere:
//
// - ``SectionStatus`` is what a section shows in place of rows it does not have.
// - `arriving(_:hasRows:title:…)` wraps a section's rows and draws the status
//   instead while there are none.
// - `reveals(_:hasRows:title:)`, `revealed(order:)` and `revealedText()` play the
//   reveal when rows arrive from the network after a wait, and only then.
//
// - `newMark(_:in:)` marks a row a refresh added or changed, and writes it in
//   again when that happens under the student's eyes; `clearsNewMarks(in:)`
//   takes the marks away once the section has been looked at.
//
// What to draw when is decided by ``SectionStage`` and ``RevealPlan``.

// MARK: - The reveal's state

/// Whether the section a view sits in is revealing its rows right now.
nonisolated struct SectionReveal: Equatable, Sendable {
    /// Rows that appear now fade in rather than being there at once.
    var plays = false
    /// Reduce Motion is on: a cross-fade, nothing moving.
    var reduced = false
}

extension SectionReveal {
    /// A change that takes effect now, replacing whatever was animating.
    @MainActor static var atOnce: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

extension EnvironmentValues {
    /// The reveal of the section around a view. Set by `reveals(_:hasRows:title:)`.
    @Entry var reveal = SectionReveal()
}

/// Lets a scroll anywhere end every reveal in progress.
@MainActor
@Observable
final class RevealSession {
    /// The app's one session.
    static let shared = RevealSession()

    /// Bumped when the student scrolls while something is being revealed.
    private(set) var interruptions = 0
    /// How many sections are revealing.
    @ObservationIgnored private var playing = 0

    /// A section started its reveal.
    func began() { playing += 1 }
    /// A section's reveal is over.
    func ended() { playing = max(0, playing - 1) }

    /// The student touched the page. Nothing changes unless a reveal is playing,
    /// so an ordinary scroll redraws no section.
    func interrupt() {
        if playing > 0 { interruptions += 1 }
    }
}

// MARK: - A section that reveals

/// Watches a section go from waiting to having rows, and plays the reveal for
/// that moment alone.
///
/// Rows that are there when the screen opens, a stored copy, a day paged to: none
/// of those is an arrival, and none is animated. Content that fades in every time
/// it is looked at stops meaning "this is new".
private struct RevealsModifier: ViewModifier {
    let phase: LoadPhase
    let hasRows: Bool
    let title: LocalizedStringResource

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off unless the student asks for a tap when something arrives.
    @AppStorage("arrivalHaptic") private var haptic = false
    /// The section was last seen waiting, without rows.
    @State private var wasWaiting = false
    @State private var waitBegan: ContinuousClock.Instant?
    @State private var playing = false
    @State private var arrivals = 0
    @State private var ending: Task<Void, Never>?

    /// 0 waiting without rows, 1 rows, 2 anything else.
    private var state: Int {
        if hasRows { return 1 }
        if case .waiting = phase { return 0 }
        return 2
    }

    /// Decided while drawing, not after: the rows must come up hidden in the
    /// very pass they first appear in.
    private var plays: Bool {
        playing || (hasRows && wasWaiting && phase == .arrived)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.reveal, SectionReveal(plays: plays, reduced: reduceMotion))
            .onAppear { note(state) }
            .onChange(of: state) { _, new in note(new) }
            .onChange(of: RevealSession.shared.interruptions) { stop() }
            .simultaneousGesture(TapGesture().onEnded { stop() }, isEnabled: playing)
            .sensoryFeedback(.impact(weight: .light), trigger: arrivals)
            .onDisappear { stop() }
    }

    private func note(_ state: Int) {
        switch state {
        case 0:
            if !wasWaiting {
                wasWaiting = true
                waitBegan = .now
            }
        case 1:
            guard wasWaiting else { return }
            let waited = waitBegan.map { ContinuousClock.now - $0 } ?? .zero
            wasWaiting = false
            waitBegan = nil
            guard phase == .arrived else { return }
            play()
            // A wait long enough to have looked away from.
            if waited >= SectionStage.patience {
                AccessibilityNotification.Announcement(String(localized: "\(String(localized: title)): caricato")).post()
                if haptic { arrivals += 1 }
            }
        default:
            wasWaiting = false
            waitBegan = nil
        }
    }

    private func play() {
        ending?.cancel()
        if !playing {
            playing = true
            RevealSession.shared.began()
        }
        let length = reduceMotion ? RevealPlan.reduced : RevealPlan.total
        ending = Task {
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// A tap or a scroll: everything is in place at once.
    private func stop() {
        ending?.cancel()
        finish()
    }

    private func finish() {
        guard playing else { return }
        playing = false
        RevealSession.shared.ended()
    }
}

/// One row of a revealing section: clear, sharp and in place a moment after the
/// row above it.
private struct RevealedModifier: ViewModifier {
    let order: Int

    @Environment(\.reveal) private var reveal
    /// How far in the row is, or `nil` before it has appeared.
    @State private var progress: Double?

    func body(content: Content) -> some View {
        let shown = progress ?? (reveal.plays ? 0 : 1)
        content
            .opacity(shown)
            .blur(radius: reveal.reduced ? 0 : 6 * (1 - shown))
            .offset(y: reveal.reduced ? 0 : 2 * (1 - shown))
            .onAppear {
                guard progress == nil else { return }
                guard reveal.plays else {
                    progress = 1
                    return
                }
                let animation: Animation = reveal.reduced
                    ? .easeInOut(duration: RevealPlan.reduced)
                    : .easeOut(duration: RevealPlan.item).delay(RevealPlan.delay(order: order))
                withAnimation(animation) { progress = 1 }
            }
            .onChange(of: reveal.plays) { _, plays in
                if !plays { settle() }
            }
    }

    /// Puts the row in place now, whatever was still animating. A value set to
    /// what it already is replaces nothing, so it is nudged and then set.
    private func settle() {
        guard progress != nil else { return }
        withTransaction(SectionReveal.atOnce) { progress = 0.999 }
        Task {
            withTransaction(SectionReveal.atOnce) { progress = 1 }
        }
    }
}

// MARK: - Text

/// Draws a text coming into focus piece by piece, the way generated text does:
/// each piece of the first lines goes from clear and blurred to sharp, a little
/// after the one before; the lines below fade as one.
struct RevealRenderer: TextRenderer, Animatable {
    /// How far the whole reveal is, 0 to 1.
    var progress: Double
    /// A single fade of the whole text, for Reduce Motion.
    var plain = false

    /// What SwiftUI animates.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Draws the text as it is at ``progress``.
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard progress < 1 else {
            for line in layout { context.draw(line) }
            return
        }
        if plain {
            var faded = context
            faded.opacity = max(0, progress)
            for line in layout { faded.draw(line) }
            return
        }
        var slices: [Text.Layout.RunSlice] = []
        var below: [Text.Layout.Line] = []
        for (number, line) in layout.enumerated() {
            if number < RevealPlan.lines {
                for run in line {
                    for slice in run { slices.append(slice) }
                }
            } else {
                below.append(line)
            }
        }
        let units = (slices.count + RevealPlan.glyphsPerUnit - 1) / RevealPlan.glyphsPerUnit
        for (index, slice) in slices.enumerated() {
            let local = RevealPlan.progress(ofUnit: index / RevealPlan.glyphsPerUnit, of: units, at: progress)
            guard local > 0 else { continue }
            var piece = context
            piece.opacity = local
            if local < 1 {
                piece.addFilter(.blur(radius: 6 * (1 - local)))
                piece.translateBy(x: 0, y: 2 * (1 - local))
            }
            piece.draw(slice, options: .disablesSubpixelQuantization)
        }
        var rest = context
        rest.opacity = max(0, progress)
        for line in below { rest.draw(line) }
    }
}

/// A text of a revealing section, drawn through ``RevealRenderer``.
private struct RevealedTextModifier: ViewModifier {
    @Environment(\.reveal) private var reveal
    @State private var progress: Double?

    func body(content: Content) -> some View {
        content
            .textRenderer(RevealRenderer(progress: progress ?? (reveal.plays ? 0 : 1), plain: reveal.reduced))
            .onAppear {
                guard progress == nil else { return }
                guard reveal.plays else {
                    progress = 1
                    return
                }
                withAnimation(.linear(duration: reveal.reduced ? RevealPlan.reduced : RevealPlan.total)) {
                    progress = 1
                }
            }
            .onChange(of: reveal.plays) { _, plays in
                guard !plays, progress != nil else { return }
                withTransaction(SectionReveal.atOnce) { progress = 0.999 }
                Task {
                    withTransaction(SectionReveal.atOnce) { progress = 1 }
                }
            }
    }
}

// MARK: - A section without rows

/// What a section shows in place of rows it does not have: nothing for an
/// instant, then a waiting line, then what it is waiting for; a failure with its
/// retry; or, only once its part has answered, the empty state.
struct SectionStatus<Empty: View>: View {
    /// Where the section's part is.
    let phase: LoadPhase
    /// The section's name, for the waiting line, the failure and VoiceOver.
    let title: LocalizedStringResource
    /// Whether to draw the name over the waiting line. `false` where the screen
    /// already draws the section's title.
    var showsTitle = true
    /// What is being waited for, said after three seconds.
    var step: LocalizedStringResource?
    /// The name the section's height is remembered under, if it is.
    var memory: String?
    /// Asks again, for a section that failed.
    var retry: (() async -> Void)?
    /// The empty state.
    @ViewBuilder var empty: Empty

    /// How long this view has been waiting.
    @State private var waited: Duration = .zero
    @State private var retrying = false

    private var isWaiting: Bool {
        if case .waiting = phase { return true }
        return false
    }

    /// The height the section had last time, held while it waits.
    private var held: CGFloat? {
        memory.flatMap { ShapeMemory.shared.height(for: $0) }
    }

    /// The view's content.
    var body: some View {
        Group {
            switch SectionStage(phase, hasRows: false, waited: waited) {
            case .content:
                EmptyView()
            case .quiet:
                Color.clear
                    .frame(height: held ?? 0)
                    .accessibilityHidden(true)
            case .waiting(let showsStep):
                waitingLine(showsStep: showsStep)
                    .frame(minHeight: held, alignment: .topLeading)
            case .empty:
                empty
            case .failed:
                failure
            }
        }
        .task(id: isWaiting) {
            waited = .zero
            guard isWaiting else { return }
            var already = Duration.zero
            if case .waiting(let since) = phase { already = since }
            let began = ContinuousClock.now
            waited = already
            while let next = SectionStage.nextChange(after: waited) {
                try? await Task.sleep(for: next + .milliseconds(10))
                if Task.isCancelled { return }
                waited = already + (ContinuousClock.now - began)
            }
        }
    }

    private func waitingLine(showsStep: Bool) -> some View {
        let stepText: LocalizedStringResource = step ?? "Il Politecnico non ha ancora risposto"
        return VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            WaitingLine()
            if showsStep {
                Text(stepText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: showsStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Caricamento, \(Text(title))"))
        .accessibilityValue(showsStep ? Text(stepText) : Text(verbatim: ""))
        .accessibilityIdentifier("section-waiting")
    }

    private var failure: some View {
        HStack(spacing: 10) {
            Label {
                Text("\(Text(title)) non disponibile")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let retry {
                Button {
                    guard !retrying else { return }
                    retrying = true
                    Task {
                        await retry()
                        retrying = false
                    }
                } label: {
                    if retrying { ProgressView() } else { Text("Riprova") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(retrying)
                .accessibilityIdentifier("section-retry")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityIdentifier("section-failed")
    }
}

/// The one soft line a waiting section draws where its first line of text will
/// be. It breathes; with Reduce Motion it stays still.
private struct WaitingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(maxWidth: 180)
            .frame(height: 8)
            .opacity(reduceMotion ? 0.8 : (lit ? 1 : 0.45))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lit = true }
            }
    }
}

/// Says that the rows under it are a stored copy, and how old, while the part
/// they belong to is still being waited for.
struct LateLabel: View {
    /// Seconds since the copy was fetched.
    let age: TimeInterval

    var body: some View {
        Label(Self.text(age: age), systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .transition(.opacity)
            .accessibilityIdentifier("section-late")
    }

    /// The label for a copy of some age.
    ///
    /// - Parameter age: Seconds since the copy was fetched.
    nonisolated static func text(age: TimeInterval) -> String {
        let minutes = Int(max(0, age) / 60)
        let when: String
        switch minutes {
        case ..<1: when = String(localized: "di poco fa")
        case ..<60: when = String(localized: "di \(minutes) min fa")
        case ..<120: when = String(localized: "di un'ora fa")
        case ..<2880: when = String(localized: "di \(minutes / 60) ore fa")
        default: when = String(localized: "di \(minutes / 1440) giorni fa")
        }
        return String(localized: "Dati \(when), sto aggiornando")
    }
}

// MARK: - New and changed rows

/// A row a refresh added or changed: a dot until its section has been looked
/// at, and the row's own reveal when the change lands while it is on screen.
///
/// Only these rows move on a refresh. The rest of the section was there and
/// stays as it is, so what moves is what is new.
private struct NewMarkModifier: ViewModifier {
    let ids: [String]
    let section: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the row's reveal is; 1 at rest.
    @State private var progress = 1.0
    @State private var playing = false
    @State private var ending: Task<Void, Never>?

    private var isNew: Bool {
        ids.contains { NewMarks.shared.isNew($0, in: section) }
    }

    func body(content: Content) -> some View {
        let isNew = isNew
        content
            .opacity(progress)
            .blur(radius: reduceMotion ? 0 : 6 * (1 - progress))
            .offset(y: reduceMotion ? 0 : 2 * (1 - progress))
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .padding(8)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: RevealPlan.reduced), value: isNew)
            .accessibilityValue(isNew ? Text("Nuovo") : Text(verbatim: ""))
            .onAppear {
                // Added by the refresh that just ended, not marked days ago.
                if ids.contains(where: { NewMarks.shared.justMarked($0, in: section) }) { play() }
            }
            .onChange(of: isNew) { _, new in
                if new { play() }
            }
            .onChange(of: RevealSession.shared.interruptions) { settle() }
            .onDisappear { settle() }
    }

    private func play() {
        ending?.cancel()
        if !playing {
            playing = true
            RevealSession.shared.began()
        }
        withTransaction(SectionReveal.atOnce) { progress = 0 }
        let length = reduceMotion ? RevealPlan.reduced : RevealPlan.item
        ending = Task {
            withAnimation(reduceMotion ? .easeInOut(duration: length) : .easeOut(duration: length)) { progress = 1 }
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// A scroll, or the row going away: in place at once.
    private func settle() {
        guard playing else { return }
        ending?.cancel()
        withTransaction(SectionReveal.atOnce) { progress = 0.999 }
        Task {
            withTransaction(SectionReveal.atOnce) { progress = 1 }
        }
        finish()
    }

    private func finish() {
        guard playing else { return }
        playing = false
        RevealSession.shared.ended()
    }
}

/// Takes a section's marks away once it has been on screen long enough to have
/// been looked at: when the student moves on, or puts the app away.
private struct ClearsNewMarksModifier: ViewModifier {
    let section: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared: ContinuousClock.Instant?

    func body(content: Content) -> some View {
        content
            .onAppear { appeared = .now }
            .onDisappear { leave() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    leave()
                } else if phase == .active, appeared == nil {
                    appeared = .now
                }
            }
    }

    private func leave() {
        guard let appeared else { return }
        self.appeared = nil
        if NewMarks.wasSeen(shownFor: ContinuousClock.now - appeared) { NewMarks.shared.seen(section) }
    }
}

/// A section's rows, or its status while it has none.
private struct ArrivingModifier<Empty: View>: ViewModifier {
    let phase: LoadPhase
    let hasRows: Bool
    let title: LocalizedStringResource
    let showsTitle: Bool
    let step: LocalizedStringResource?
    let memory: String?
    let retry: (() async -> Void)?
    let empty: Empty

    /// How old the copy on screen is, when it stands in for a slow part.
    private var lateAge: TimeInterval? {
        if case .late(let age) = phase { return age }
        return nil
    }

    func body(content: Content) -> some View {
        Group {
            if hasRows {
                VStack(alignment: .leading, spacing: 8) {
                    if let lateAge { LateLabel(age: lateAge) }
                    content
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if let memory { ShapeMemory.shared.remember(height, for: memory) }
                        }
                }
                .animation(.easeOut(duration: RevealPlan.reduced), value: lateAge != nil)
            } else {
                SectionStatus(phase: phase, title: title, showsTitle: showsTitle, step: step,
                              memory: memory, retry: retry) { empty }
            }
        }
        .reveals(phase, hasRows: hasRows, title: title)
    }
}

extension View {
    /// Draws this section's rows when it has some, and otherwise what its part
    /// is doing: waiting, failed, or answered with nothing.
    ///
    /// - Parameters:
    ///   - phase: Where the section's part is.
    ///   - hasRows: Whether there is anything to draw.
    ///   - title: The section's name. A fixed word.
    ///   - showsTitle: Whether the waiting line carries the name.
    ///   - step: What is being waited for, said after three seconds.
    ///   - memory: The name to remember the section's height under.
    ///   - retry: Asks again, for a section that failed.
    ///   - empty: The empty state, shown only once the part has answered.
    func arriving(_ phase: LoadPhase, hasRows: Bool, title: LocalizedStringResource,
                  showsTitle: Bool = true, step: LocalizedStringResource? = nil,
                  remember memory: String? = nil, retry: (() async -> Void)? = nil,
                  @ViewBuilder empty: () -> some View) -> some View {
        modifier(ArrivingModifier(phase: phase, hasRows: hasRows, title: title, showsTitle: showsTitle,
                                  step: step, memory: memory, retry: retry, empty: empty()))
    }

    /// Plays the reveal on this section's `revealed(order:)` rows when they
    /// arrive from the network after a wait. For a section that draws its own
    /// status; `arriving` already includes it.
    func reveals(_ phase: LoadPhase, hasRows: Bool, title: LocalizedStringResource) -> some View {
        modifier(RevealsModifier(phase: phase, hasRows: hasRows, title: title))
    }

    /// Marks a row of a revealing section.
    ///
    /// - Parameter order: Its place in the section, from 0.
    func revealed(order: Int) -> some View {
        modifier(RevealedModifier(order: order))
    }

    /// Marks a text of a revealing section to come into focus piece by piece.
    func revealedText() -> some View {
        modifier(RevealedTextModifier())
    }

    /// Marks this row as new while one of its items is, and writes it in again
    /// when a refresh changes it on screen.
    ///
    /// - Parameters:
    ///   - ids: The identities of the items the row shows.
    ///   - section: The section the items are marked in.
    func newMark(_ ids: [String], in section: String) -> some View {
        modifier(NewMarkModifier(ids: ids, section: section))
    }

    /// Marks this row as new while its item is.
    ///
    /// - Parameters:
    ///   - id: The item's identity.
    ///   - section: The section the item is marked in.
    func newMark(_ id: String, in section: String) -> some View {
        newMark([id], in: section)
    }

    /// Removes the marks of a section once this view, which shows it, has been
    /// on screen.
    ///
    /// - Parameter section: The section.
    func clearsNewMarks(in section: String) -> some View {
        modifier(ClearsNewMarksModifier(section: section))
    }

    /// Ends every reveal in progress when the student scrolls this view.
    func endsRevealsOnScroll() -> some View {
        onScrollPhaseChange { _, phase in
            if phase == .interacting { RevealSession.shared.interrupt() }
        }
    }
}

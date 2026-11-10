import SwiftUI

/// Times one opening of a screen for the ``LoadingLedger``.
///
/// From the moment the screen appears, it notes how long its first content took
/// and how long until everything it shows was there. A screen left before then is
/// noted with what it reached, so an opening the student gave up on still counts.
private struct ScreenLedgerModifier: ViewModifier {
    let name: String
    let hasContent: Bool
    let isComplete: Bool

    @State private var opened: Date?
    @State private var began: ContinuousClock.Instant?
    @State private var firstContent: Int?
    @State private var isNoted = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                opened = .now
                began = ContinuousClock.now
                firstContent = nil
                isNoted = false
                mark()
            }
            .onChange(of: hasContent) { mark() }
            .onChange(of: isComplete) { mark() }
            .onDisappear { note(complete: nil) }
    }

    /// Milliseconds since the screen appeared.
    private var elapsed: Int? {
        guard let began else { return nil }
        let time = ContinuousClock.now - began
        return Int(time.components.seconds) * 1000 + Int(time.components.attoseconds / 1_000_000_000_000_000)
    }

    private func mark() {
        guard !isNoted, let elapsed else { return }
        if hasContent, firstContent == nil { firstContent = elapsed }
        if isComplete { note(complete: elapsed) }
    }

    private func note(complete: Int?) {
        guard !isNoted, let opened else { return }
        isNoted = true
        LoadingLedger.shared.note(LedgerScreen(
            screen: name, opened: opened, firstContent: firstContent ?? complete, complete: complete))
    }
}

extension View {
    /// Times this screen's loading for the loading ledger.
    ///
    /// - Parameters:
    ///   - name: The screen's name in the report. A fixed word, never data.
    ///   - hasContent: Whether the screen shows any real data yet.
    ///   - isComplete: Whether everything the screen shows is there.
    func screenLedger(_ name: String, hasContent: Bool, isComplete: Bool) -> some View {
        modifier(ScreenLedgerModifier(name: name, hasContent: hasContent, isComplete: isComplete))
    }
}

import Foundation

/// Sends the Watch what the phone currently knows.
///
/// Three moments call it, and they need the same snapshot: the interface
/// noticing that the timetable changed, the hourly background refresh, and
/// the Watch asking because what it holds has gone stale. The narrowing lives
/// in ``WatchSnapshotBuilder``; this is only where the app's models meet it.
@MainActor
enum WatchSync {
    /// Builds a snapshot from the models and sends it.
    ///
    /// Nothing is sent with the sample data on: sample lectures on a wrist
    /// would send someone to a room that does not exist.
    ///
    /// - Parameters:
    ///   - agenda: The timetable.
    ///   - career: The sittings.
    ///   - session: The account, for the career figures and the sample switch.
    static func send(agenda: AgendaModel, career: CareerModel, session: Session) {
        // The Mac has no Watch to talk to: WatchConnectivity is not on macOS.
        #if canImport(WatchConnectivity)
        guard !session.useMockData else { return }
        let figures = session.student.flatMap {
            OfflineStore.shared.load(CareerSnapshot.self,
                                     as: CareerSnapshot.cacheName,
                                     account: $0.matricola)?.value
        }
        WatchBridge.shared.send(WatchSnapshotBuilder.build(
            events: agenda.events, exams: career.sessions, day: .now, career: figures))
        #endif
    }

    /// Answers the Watch asking for a fresh snapshot: loads what is due, then
    /// sends.
    ///
    /// Not forced. The Watch asks because it has not heard from the phone,
    /// not because the phone's own data is old, so the loads' own windows
    /// decide whether the network is needed — and when the phone was woken
    /// in the background to answer, it has only seconds to spend.
    ///
    /// - Parameters:
    ///   - agenda: The timetable.
    ///   - career: The sittings.
    ///   - session: The account.
    static func answer(agenda: AgendaModel, career: CareerModel, session: Session) async {
        guard !session.useMockData else { return }
        async let lectures: Void = agenda.load()
        async let sittings: Void = career.load()
        _ = await (lectures, sittings)
        send(agenda: agenda, career: career, session: session)
    }
}

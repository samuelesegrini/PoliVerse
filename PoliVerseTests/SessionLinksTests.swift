import Testing
@testable import PoliVerse

@Suite("Account linking", .timeLimit(.minutes(1)))
@MainActor
struct SessionLinksTests {
    /// Deliberately ignores cancellation, like a network completion already queued.
    @MainActor
    final class Check {
        private var result: CheckedContinuation<SessionLinks.Status, Never>?
        private var started: CheckedContinuation<Void, Never>?
        private var hasStarted = false

        func run() async -> SessionLinks.Status {
            await withCheckedContinuation {
                result = $0
                hasStarted = true
                started?.resume()
                started = nil
            }
        }

        func waitUntilStarted() async {
            if hasStarted { return }
            await withCheckedContinuation { started = $0 }
        }

        func finish(_ status: SessionLinks.Status) {
            result?.resume(returning: status)
            result = nil
        }
    }

    @Test("Connections start together and publish results independently")
    func concurrentConnections() async {
        let materials = Check(), archive = Check()
        var cleaned = false
        let links = SessionLinks { connection, fresh, _ in
            #expect(fresh)
            return await (connection == .weBeep ? materials : archive).run()
        } finishLogin: { cleaned = true }
        links.connect(freshLogin: true)
        await materials.waitUntilStarted()
        await archive.waitUntilStarted()
        #expect(links[.university] == .connected)
        archive.finish(.connected)
        await links.settle(.recordings)
        #expect(links[.recordings] == .connected)
        #expect(links[.weBeep] == .connecting)
        #expect(!cleaned)
        materials.finish(.needsSignIn)
        await links.settle()
        #expect(links[.weBeep] == .needsSignIn)
        #expect(cleaned)
    }

    @Test("A late result after sign-out cannot restore state or run login cleanup")
    func cancelledAccount() async {
        let check = Check()
        var cleaned = false
        let links = SessionLinks { connection, _, _ in
            if connection == .weBeep { return await check.run() }
            return .connected
        } finishLogin: { cleaned = true }
        links.connect(freshLogin: true)
        await check.waitUntilStarted()
        let stopping = Task { await links.stop() }
        while links[.weBeep] != .idle { await Task.yield() }
        check.finish(.connected)
        await stopping.value
        #expect(links[.weBeep] == .idle)
        #expect(links[.recordings] == .idle)
        #expect(!cleaned)
    }

    @Test("Repeated requests join work; retry checks only the requested connection")
    func joinsAndRetries() async {
        let check = Check()
        var calls: [SessionLinks.Connection] = []
        let links = SessionLinks { connection, fresh, _ in
            #expect(!fresh)
            calls.append(connection)
            if connection == .weBeep, calls.filter({ $0 == .weBeep }).count == 1 {
                return await check.run()
            }
            return .connected
        }
        links.connect()
        await check.waitUntilStarted()
        links.connect()
        links.retry(.weBeep)
        check.finish(.unavailable)
        await links.settle()
        #expect(calls.filter { $0 == .weBeep }.count == 1)
        #expect(calls.filter { $0 == .recordings }.count == 1)
        links.retry(.weBeep)
        await links.settle()
        #expect(calls.filter { $0 == .weBeep }.count == 2)
        #expect(calls.filter { $0 == .recordings }.count == 1)
        #expect(links[.weBeep] == .connected)
    }

    @Test("Progress advances only at milestones and ignores callbacks from an old attempt")
    func milestoneProgress() async {
        let first = Check(), second = Check()
        var reports: [SessionLinks.Report] = []
        let links = SessionLinks { connection, _, report in
            guard connection == .weBeep else { return .connected }
            reports.append(report)
            return await (reports.count == 1 ? first : second).run()
        }
        links.connect()
        await first.waitUntilStarted()
        #expect(links.progress(for: .weBeep) == 0.25)
        reports[0](.accessVerified)
        #expect(links.progress(for: .weBeep) == 0.75)
        reports[0](.sessionReady)
        #expect(links.progress(for: .weBeep) == 0.75)
        first.finish(.unavailable)
        await links.settle()

        links.retry(.weBeep)
        await second.waitUntilStarted()
        reports[0](.ready)
        #expect(links.progress(for: .weBeep) == 0.25)
        reports[1](.sessionReady)
        #expect(links.progress(for: .weBeep) == 0.5)
        second.finish(.connected)
        await links.settle()
        #expect(links.progress(for: .weBeep) == 1)
    }

    @Test(arguments: [SessionLinks.Status.offline, .unavailable, .needsSignIn])
    func failureDoesNotBlockOtherConnections(_ failure: SessionLinks.Status) async {
        let links = SessionLinks { connection, _, _ in connection == .weBeep ? failure : .connected }
        links.connect()
        await links.settle()
        #expect(links[.weBeep] == failure)
        #expect(links[.recordings] == .connected)
    }
}

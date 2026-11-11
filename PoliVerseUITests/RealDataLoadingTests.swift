import XCTest

/// The loading by parts, watched on the account signed in on the device.
///
/// Sample data answers at once and whole, so on it a section never waits, never
/// fails and never holds a stored copy: none of what `SectionKit` draws for those
/// moments is ever on screen. These tests put the real network behind the same
/// screens and watch what a student would see while the answers come in.
///
/// Opt-in exactly as ``RealDataPerformanceTests``: only the **PoliVerseRealData**
/// scheme runs the class, nobody signed in is a skip, and no test types a
/// credential. The tests only read; two of them empty the app's offline copies
/// first, through Impostazioni's own "Svuota cache", which the next refresh
/// rebuilds.
///
/// What the network is like is the one thing a test cannot see, so the run says
/// it: `POLIVERSE_NETWORK`, passed by `xcodebuild` as
/// `TEST_RUNNER_POLIVERSE_NETWORK`.
///
/// - `good`, the default: every section ends with its content or its empty state.
/// - `slow`, with the Network Link Conditioner on "Very Bad Network": the waiting
///   line has to show, and say what it waits for once the wait is long.
/// - `down`, with "100% Loss": a section with nothing to show says the failure
///   and offers to retry; a section with a stored copy keeps showing it.
///
/// Each test prints what it timed on lines starting with `LOADING`, since the
/// scheme keeps no attachments.
nonisolated final class RealDataLoadingTests: PoliVerseUITestCase {
    /// What the run was told the network is like.
    private enum Network: String { case good, slow, down }

    private var network: Network {
        Network(rawValue: ProcessInfo.processInfo.environment["POLIVERSE_NETWORK"] ?? "") ?? .good
    }

    /// How long a section may take to stop waiting, one way or the other: a
    /// request that gets no answer gives up at its timeout, not before.
    private var limit: TimeInterval { network == .good ? 45 : 150 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["POLIVERSE_REAL_DATA"] == "1",
            "Real-data loading tests run only from the PoliVerseRealData scheme")
    }

    // MARK: Watching a screen

    /// What was on screen while a screen loaded, sampled a few times a second.
    private struct Watch {
        /// Seconds from the start to the first sample with a waiting line.
        var firstWaiting: TimeInterval?
        /// Seconds from the start to the last sample with a waiting line.
        var lastWaiting: TimeInterval?
        /// Whether a waiting line said what it was waiting for.
        var sawStep = false
        /// Seconds from the start to the first failure line.
        var firstFailure: TimeInterval?
        /// Whether a failure line offered to retry.
        var sawRetry = false
        /// The empty-state sentences seen at any time.
        var emptySeen: Set<String> = []
        /// The empty-state sentences on screen at the last sample.
        var emptyAtEnd: Set<String> = []
        /// Whether a section was still waiting at the last sample.
        var waitingAtEnd = false
        /// Whether a failure line was on screen at the last sample.
        var failedAtEnd = false
        /// How many times the screen was looked at.
        var samples = 0
        /// How long the watch lasted.
        var length: TimeInterval = 0

        var line: String {
            func seconds(_ value: TimeInterval?) -> String { value.map { String(format: "%.1f", $0) } ?? "-" }
            return "firstWaiting=\(seconds(firstWaiting)) lastWaiting=\(seconds(lastWaiting)) step=\(sawStep) "
                + "firstFailure=\(seconds(firstFailure)) retry=\(sawRetry) waitingAtEnd=\(waitingAtEnd) "
                + "failedAtEnd=\(failedAtEnd) empty=\(emptySeen.sorted()) samples=\(samples) "
                + "length=\(seconds(length))"
        }
    }

    /// Looks at the screen until nothing has been waiting for a while, or the
    /// limit passes.
    ///
    /// - Parameters:
    ///   - app: The app to watch.
    ///   - empties: The empty-state sentences this screen can show.
    ///   - atLeast: How long to watch even when nothing waits.
    @MainActor private func watch(
        _ app: XCUIApplication, empties: [String] = [], atLeast: TimeInterval = 8
    ) -> Watch {
        var seen = Watch()
        let began = Date()
        let waiting = app.descendants(matching: .any).matching(identifier: "section-waiting")
        let failed = app.descendants(matching: .any).matching(identifier: "section-failed")
        let retry = app.buttons.matching(identifier: "section-retry")
        while true {
            let now = Date().timeIntervalSince(began)
            seen.samples += 1
            let line = waiting.firstMatch
            seen.waitingAtEnd = line.exists
            if seen.waitingAtEnd {
                if seen.firstWaiting == nil { seen.firstWaiting = now }
                seen.lastWaiting = now
                if let step = line.value as? String, !step.isEmpty { seen.sawStep = true }
            }
            seen.failedAtEnd = failed.firstMatch.exists
            if seen.failedAtEnd {
                if seen.firstFailure == nil { seen.firstFailure = now }
                if retry.firstMatch.exists { seen.sawRetry = true }
            }
            seen.emptyAtEnd = Set(empties.filter { app.staticTexts[$0].firstMatch.exists })
            seen.emptySeen.formUnion(seen.emptyAtEnd)
            seen.length = Date().timeIntervalSince(began)
            let quietFor = seen.length - (seen.lastWaiting ?? 0)
            if seen.length >= limit { break }
            if !seen.waitingAtEnd, seen.length >= atLeast, quietFor >= 4 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return seen
    }

    /// What every screen owes whatever the network: a wait ends, an empty state
    /// is never taken back, and the network the run named shows the way it should.
    @MainActor private func check(_ seen: Watch, on screen: String, startedEmpty: Bool) {
        print("LOADING \(screen) network=\(network.rawValue) \(seen.line)")
        XCTAssertFalse(seen.waitingAtEnd, "\(screen): a section was still waiting after \(Int(limit)) s")
        // R2: a section may say it is empty only once its part has answered, so
        // an empty state that later gives way to rows was said too early.
        let takenBack = seen.emptySeen.subtracting(seen.emptyAtEnd)
        XCTAssertTrue(takenBack.isEmpty, "\(screen): said \(takenBack.sorted()) and then showed something else")
        switch network {
        case .good:
            XCTAssertFalse(seen.failedAtEnd, "\(screen): a section failed on a good network")
        case .slow:
            guard startedEmpty else { break }
            XCTAssertNotNil(seen.firstWaiting, "\(screen): nothing said it was waiting on a slow network")
            if let first = seen.firstWaiting, let last = seen.lastWaiting, last - first > 4 {
                XCTAssertTrue(seen.sawStep, "\(screen): waited \(Int(last - first)) s without saying for what")
            }
        case .down:
            guard startedEmpty else { break }
            XCTAssertNotNil(seen.firstFailure, "\(screen): no section said the failure with no network")
            XCTAssertTrue(seen.sawRetry, "\(screen): the failure did not offer to retry")
        }
    }

    // MARK: Emptying the copies

    /// Empties the app's offline copies from Impostazioni and closes the app, so
    /// the next launch has nothing to show until the network answers.
    @MainActor private func emptyCopies() throws {
        let app = try launchSignedIn(forcingRefresh: false)
        let profile = app.buttons["bar-profile"].firstMatch
        if profile.waitForExistence(timeout: 10) {
            profile.tap()
            goBack(app)  // the profile opens one page in
        } else {
            tap(app.buttons["bar-settings"].firstMatch, "Neither bar button is on screen")
        }
        require(app.descendants(matching: .any)["settings-list"].firstMatch, "Impostazioni did not open")
        tap(app.descendants(matching: .any)["settings-status-data"].firstMatch, "Impostazioni has no Dati tile")
        let clear = app.buttons["Svuota cache"].firstMatch
        for _ in 0..<6 where !(clear.exists && clear.isHittable) { app.swipeUp() }
        require(clear, "Dati e archiviazione has no Svuota cache")
        // Disabled until the first scan is in, and for good when there is
        // nothing to clear.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: clear)
        if XCTWaiter().wait(for: [enabled], timeout: 15) == .completed {
            clear.tap()
            // With nothing left the button goes grey: said in the log, so a run
            // whose copies were still there is not read as an empty start.
            let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: clear)
            let emptied = XCTWaiter().wait(for: [disabled], timeout: 5) == .completed
            print("LOADING copies emptied=\(emptied)")
        } else {
            print("LOADING copies emptied=already")
        }
        app.terminate()
    }

    // MARK: Stored copies

    /// R6, R23: with copies on disk the app opens on them, and a refresh behind
    /// them, whether it lands or fails, never puts a waiting line or a failure
    /// in the place of rows already shown.
    @MainActor func testCopiesOpenTheAppAtOnce() throws {
        if network != .down {
            // A full refresh first, left to finish, so every copy is on disk.
            let first = try launchSignedIn()
            sleep(20)
            first.terminate()
        }
        let began = Date()
        let app = try launchSignedIn()
        print(String(format: "LOADING oggi-warm reached=%.1f", Date().timeIntervalSince(began)))
        let oggi = watch(app, atLeast: 12)
        print("LOADING oggi-warm network=\(network.rawValue) \(oggi.line)")
        XCTAssertNil(oggi.firstWaiting, "Oggi waited although its copies were on disk")

        switchTab(app, to: "Carriera", expecting: "tab-career")
        let carriera = watch(app, atLeast: 6)
        print("LOADING carriera-warm network=\(network.rawValue) \(carriera.line)")
        XCTAssertNil(carriera.firstWaiting, "Carriera waited although its copies were on disk")
        XCTAssertNil(carriera.firstFailure, "Carriera showed a failure in the place of its stored copy")
    }

    // MARK: Nothing on disk

    /// R1, R2, R5, R6 on Oggi: with nothing on disk each section waits for its
    /// own part, and ends with rows, its empty state, or its failure.
    @MainActor func testEmptyStartOnOggi() throws {
        try emptyCopies()
        let app = makeSignedInApp()
        let began = Date()
        app.launch()
        if !app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 60) {
            if app.buttons["Codice persona e password"].firstMatch.exists {
                throw XCTSkip("Nobody is signed in on this device: sign in to PoliVerse by hand, then run again")
            }
            XCTFail("The app never reached Oggi with nothing on disk")
        }
        print(String(format: "LOADING oggi-empty reached=%.1f", Date().timeIntervalSince(began)))
        check(watch(app), on: "oggi-empty", startedEmpty: true)
    }

    /// R1, R2, R3, R5, R6 on Carriera: libretto and appelli each wait for their
    /// own part, and neither says "nessun esito" before its part has answered.
    @MainActor func testEmptyStartOnCarriera() throws {
        try emptyCopies()
        let app = makeSignedInApp()
        app.launch()
        // Straight to Carriera, before the launch refresh has brought it in.
        let began = Date()
        tap(tabButton(app, "Carriera"), "The tab bar has no Carriera tab", timeout: 60)
        let seen = watch(app, empties: ["Nessun esito", "Nessun appello"])
        print(String(format: "LOADING carriera-empty settled=%.1f", Date().timeIntervalSince(began)))
        check(seen, on: "carriera-empty", startedEmpty: true)

        guard network == .down, seen.sawRetry else { return }
        // The retry asks again and, with the network still down, comes back to
        // the same failure rather than to a wait without end.
        app.buttons.matching(identifier: "section-retry").firstMatch.tap()
        let again = watch(app)
        print("LOADING carriera-retry \(again.line)")
        XCTAssertFalse(again.waitingAtEnd, "Riprova left the section waiting")
        XCTAssertTrue(again.failedAtEnd, "Riprova with no network did not come back to the failure")
    }

    // MARK: Aule libere

    /// The room count in the section's heading, "Libere ora — 12" or "12 aule".
    @MainActor private func listedRooms(in app: XCUIApplication) -> Int? {
        let heading = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES[c] %@", "^(libere ora — [0-9]+|[0-9]+ aule)$")).firstMatch
        guard heading.exists else { return nil }
        return heading.label.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    /// The pass in flight, "37 di 158 aule", as (done, total).
    @MainActor private func roomsProgress(in app: XCUIApplication) -> (done: Int, total: Int)? {
        let line = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ di [0-9]+ aule$")).firstMatch
        guard line.exists else { return nil }
        let numbers = line.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
    }

    @MainActor private func openFreeRooms(in app: XCUIApplication) {
        switchTab(app, to: "Cerca", expecting: "tab-search")
        tap(app.buttons["place-freeRooms"].firstMatch, "Cerca does not list Aule libere")
    }

    /// R9, R13: rooms are listed while the rest of the campus is still being
    /// asked, and the first of them long before the last.
    @MainActor func testRoomsArriveWhileTheCampusIsAsked() throws {
        try XCTSkipIf(network == .down, "With no network there are no rooms to arrive")
        let app = try launchSignedIn()
        openFreeRooms(in: app)
        let began = Date()
        require(app.navigationBars["Aule libere"], "Aule libere did not open", timeout: 15)

        var firstProgress: TimeInterval?
        var firstRooms: TimeInterval?
        var finished: TimeInterval?
        var listedWhileAsking = false
        var total = 0
        var listed = 0
        let roomLimit: TimeInterval = network == .good ? 120 : 300
        while Date().timeIntervalSince(began) < roomLimit {
            let now = Date().timeIntervalSince(began)
            let progress = roomsProgress(in: app)
            let rooms = listedRooms(in: app)
            if let progress {
                total = max(total, progress.total)
                if firstProgress == nil { firstProgress = now }
            }
            if let rooms, rooms > 0 {
                listed = rooms
                if firstRooms == nil { firstRooms = now }
                if progress != nil { listedWhileAsking = true }
            }
            XCTAssertFalse(app.staticTexts["Aule non disponibili"].exists, "Aule libere failed outright")
            // Over once the heading is there and no pass is in flight.
            if rooms != nil, progress == nil, now > 1 {
                finished = now
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        func seconds(_ value: TimeInterval?) -> String { value.map { String(format: "%.1f", $0) } ?? "-" }
        print("LOADING aule network=\(network.rawValue) firstProgress=\(seconds(firstProgress)) "
            + "firstRooms=\(seconds(firstRooms)) finished=\(seconds(finished)) rooms=\(listed) asked=\(total) "
            + "listedWhileAsking=\(listedWhileAsking)")
        XCTAssertNotNil(finished, "The pass over the campus was not over after \(Int(roomLimit)) s")
        // A pass the service answered from its 60-second window shows no
        // progress at all; only a pass that was seen in flight is judged.
        if firstProgress != nil, listed > 0 {
            XCTAssertTrue(listedWhileAsking, "No room was listed until the whole campus had answered")
        }
    }

    /// Hitches while rooms arrive under a list already on screen: a forced pass,
    /// which redraws the rows batch by batch.
    @MainActor func testRoomsHitchesWhileArriving() throws {
        try XCTSkipIf(network == .down, "With no network there are no rooms to arrive")
        let app = try launchSignedIn()
        openFreeRooms(in: app)
        require(app.navigationBars["Aule libere"], "Aule libere did not open", timeout: 15)
        // The first pass, left to finish, so each measured pass starts from a full list.
        let first = Date()
        while Date().timeIntervalSince(first) < 120, roomsProgress(in: app) != nil || listedRooms(in: app) == nil {
            Thread.sleep(forTimeInterval: 0.3)
        }
        let list = require(app.collectionViews.firstMatch, "Aule libere has no list")

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app), XCTClockMetric()], options: options) {
            // Pull to refresh: the screen's own forced pass.
            let top = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let bottom = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            top.press(forDuration: 0.05, thenDragTo: bottom)
            let began = Date()
            // Until the pass shows, then until it is over.
            while Date().timeIntervalSince(began) < 5, roomsProgress(in: app) == nil {
                Thread.sleep(forTimeInterval: 0.1)
            }
            while Date().timeIntervalSince(began) < 120, roomsProgress(in: app) != nil {
                list.swipeUp(velocity: .slow)
                list.swipeDown(velocity: .slow)
            }
        }
    }
}

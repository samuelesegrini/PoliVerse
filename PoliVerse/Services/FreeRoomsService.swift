import Foundation
import Observation
import OSLog

/// Which rooms are free, and when.
///
/// ## Where this came from
///
/// An earlier pass concluded that occupancy was unreachable: the CEDA hosts
/// refuse connections off campus, PoliNetwork's search sits behind Cloudflare
/// Access, and `maps_rest` answers 500 for anything about bookings. That
/// conclusion was wrong, and the reason is worth recording — `props` has
/// always listed a `ws_aule` service that was never probed:
///
/// ```
/// ws_aule.base_url = https://api.polimi.it/ws_aule
/// ws_aule.profile  = 3
/// ```
///
/// The official app's `registroLezioni` chunk calls exactly two paths on it:
///
/// ```js
/// getSedi: url: "/cata/sedi"
/// getAule: url: `/cata/aule?inizio=${fmt(a)}&fine=${fmt(b)}&sede=${sede}`
/// ```
///
/// Both answer **401** unauthenticated — the same as `/iae/v1/insegn`, which
/// this app already calls successfully — so they exist and take our token.
/// `inizio` and `fine` are `yyyy-MM-dd`; the formatter in the bundle emits no
/// time component.
///
/// ## What is still a guess
///
/// The response body, as ever. The shape is logged so one device run settles
/// it. Free time is **derived** from the bookings rather than requested: the
/// service says what is happening, and the gaps are the answer.
@Observable
final class FreeRoomsService {
    private(set) var sites: [AuleSite] = []
    private(set) var rooms: [RoomSchedule] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var payloadUnreadable = false
    /// Set when the Politecnico refuses this account the service outright.
    /// Not a failure to retry, and not a reason to offer a login.
    private(set) var notEntitled = false

    /// The profile that worked, once one has.
    ///
    /// `props` says `ws_aule.profile = 3` and the official client presets
    /// that, but 3 is a profile a student does not hold — this account
    /// reports only profile 1, "Student". The service answers "Utente non
    /// abilitato" rather than naming the problem, so the service profile is
    /// tried first (matching the official client) and the account's own
    /// profile second, and whichever answers is remembered.
    private var workingProfile: Int?

    /// The day being shown, and the campus.
    var day: Date = .now
    var siteID: String?

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "aule")
    /// Keyed by day and site, so switching back to a day already fetched does
    /// not refetch it.
    private var loadedKey: String?

    init(session: Session) {
        self.session = session
    }

    /// Rooms with at least one usable gap, ordered by how much free time they
    /// have — the room free all afternoon is more useful than the one free for
    /// forty minutes.
    func freeRooms(minimumMinutes: Int = 30) -> [(room: RoomSchedule, slots: [DateInterval])] {
        let window = teachingDay
        return rooms
            .map { ($0, $0.freeSlots(in: window, minimumMinutes: minimumMinutes)) }
            .filter { !$0.1.isEmpty }
            .sorted { left, right in
                let leftFree = left.1.reduce(0) { $0 + $1.duration }
                let rightFree = right.1.reduce(0) { $0 + $1.duration }
                if leftFree != rightFree { return leftFree > rightFree }
                return left.0.name < right.0.name
            }
    }

    /// Rooms free *right now*, which is the question actually being asked when
    /// someone opens this looking for somewhere to sit.
    func freeNow() -> [RoomSchedule] {
        let now = Date.now
        guard teachingDay.contains(now) else { return [] }
        let window = DateInterval(start: now, end: min(now.addingTimeInterval(1800), teachingDay.end))
        return rooms.filter { $0.isFree(during: window) }.sorted { $0.name < $1.name }
    }

    /// 08:00–20:00 in Rome. Outside those hours every room is trivially free,
    /// which is true and useless — the building is shut.
    var teachingDay: DateInterval {
        let start = PoliMiDate.time(8, on: day)
        let end = PoliMiDate.time(20, on: day)
        return DateInterval(start: start, end: max(start, end))
    }

    func loadSites() async {
        guard sites.isEmpty, !session.useMockData else {
            if session.useMockData { sites = MockData.auleSites() }
            return
        }
        do {
            let data = try await fetch(
                APIRequest(host: .wsAule, path: "/cata/sedi", sendsMatricola: true))
            log.notice("sedi payload shape: \(JSONShape.describe(data), privacy: .public)")
            sites = try JSONDecoder().decode(SediResponse.self, from: data).sites
            log.notice("sedi: \(self.sites.count, privacy: .public) campuses")
            if siteID == nil { siteID = sites.first?.id }
        } catch let error as APIError {
            if case .notEntitled = error { notEntitled = true }
            log.error("Sedi failed: \(error.localizedDescription)")
        } catch {
            log.error("Sedi failed: \(error.localizedDescription)")
        }
    }

    /// Sends a `ws_aule` request, trying the account's own profile if the
    /// service's configured one is refused.
    ///
    /// Only the first refusal costs an extra round trip: the profile that
    /// works is remembered for the rest of the session.
    private func fetch(_ request: APIRequest) async throws -> Data {
        var attempt = request
        attempt.profileOverride = workingProfile

        do {
            let data = try await session.api.send(attempt)
            return data
        } catch let error as APIError {
            guard case .notEntitled = error, workingProfile == nil else { throw error }

            // Second and last attempt: the signed-in user's own profile.
            let mine = session.profileID
            log.notice("ws_aule refused profile 3; retrying with \(mine, privacy: .public)")
            attempt.profileOverride = mine
            let data = try await session.api.send(attempt)
            workingProfile = mine
            return data
        }
    }

    func load(force: Bool = false) async {
        let key = "\(PoliMiDate.queryString(day))|\(siteID ?? "-")|\(session.useMockData)"
        guard !isLoading, force || key != loadedKey else { return }
        isLoading = true
        errorMessage = nil
        payloadUnreadable = false
        defer { isLoading = false }

        if session.useMockData {
            rooms = MockData.roomSchedules(on: day)
            loadedKey = key
            return
        }

        await loadSites()
        guard !notEntitled else {
            errorMessage = nil
            return
        }
        guard let siteID else {
            errorMessage = "Nessuna sede disponibile."
            return
        }

        do {
            // One day at a time: `inizio` and `fine` are dates, and the
            // official app passes the same value for both when it wants one.
            let stamp = PoliMiDate.queryString(day)
            let data = try await fetch(
                APIRequest(
                    host: .wsAule,
                    path: "/cata/aule",
                    query: [
                        .init(name: "inizio", value: stamp),
                        .init(name: "fine", value: stamp),
                        .init(name: "sede", value: siteID),
                    ],
                    sendsMatricola: true
                )
            )
            log.notice("aule payload shape: \(JSONShape.describe(data), privacy: .public)")

            let response = try JSONDecoder().decode(AuleResponse.self, from: data)
            rooms = response.rooms
            payloadUnreadable = response.rooms.isEmpty
                && !(response.raw.arrayValue?.isEmpty ?? false)
            let booked = rooms.reduce(0) { $0 + $1.bookings.count }
            log.notice("aule: \(self.rooms.count, privacy: .public) rooms, \(booked, privacy: .public) bookings, \(self.freeRooms().count, privacy: .public) with free time")
            loadedKey = key
        } catch let error as APIError {
            if case .notEntitled = error { notEntitled = true }
            log.error("Aule failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        } catch {
            log.error("Aule failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

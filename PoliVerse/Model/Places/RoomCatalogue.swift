import Foundation

/// What a screen needs from the campus catalogue.
///
/// Three members, and two modules read exactly these three —
/// ``FreeRoomsModel`` and ``CampusMapModel``. Two independent consumers of the
/// same three members is the catalogue's interface showing itself; naming it
/// only writes down what was already true.
@MainActor
protocol RoomCatalogue: AnyObject, Sendable {
    /// Every room on campus, with its building, floor and capacity.
    var rooms: [Classroom] { get }
    /// The campuses present, derived once rather than on every read.
    var campuses: [String] { get }
    /// Ensures the catalogue is loaded, which is cheap once it is.
    func load(force: Bool) async
}


/// What the map needs from the occupancy service.
///
/// Distinct from ``RoomCatalogue`` because the two answer different questions
/// against different backends: the catalogue says *where room 3.0.1 is*, the
/// availability says *what is happening in it*. They have different auth and
/// different lifetimes, which is why they were never one type.
@MainActor
protocol RoomAvailability: AnyObject, Sendable {
    var rooms: [RoomSchedule] { get }
    /// The campus being shown, which the map sets and this filters by.
    var campus: String? { get set }
    /// The rooms free at this moment.
    func freeNow() -> [RoomSchedule]
    func load(force: Bool) async
}


/// The defaults the concrete types spell on their own `load`.
///
/// A protocol requirement cannot carry one, and making every call site pass
/// `force: false` would be the seam charging rent for nothing.
extension RoomCatalogue {
    func load() async { await load(force: false) }

    /// Rooms matching a query, optionally within one campus.
    ///
    /// A default rather than a requirement: it is a filter over ``rooms`` and
    /// nothing else, so no catalogue should have to write it, and none can
    /// write it differently.
    func rooms(matching query: String, campus: String?) -> [Classroom] {
        rooms.filter { room in
            if let campus, room.campusName != campus { return false }
            guard !query.isEmpty else { return true }
            return room.id.localizedCaseInsensitiveContains(query)
                || (room.buildingName ?? "").localizedCaseInsensitiveContains(query)
                || (room.campusName ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

extension RoomCatalogue {
    /// The sites the rooms are in — "Milano Città Studi", "Como" — sorted: the
    /// places a student names, where ``campuses`` are addresses. A room whose
    /// site is unknown stands in with its campus.
    var sites: [String] {
        Array(Set(rooms.compactMap { $0.siteName ?? $0.campusName })).sorted()
    }

    /// The site with the most rooms: the likeliest guess before the student says.
    var biggestSite: String? {
        var counts: [String: Int] = [:]
        for room in rooms { if let site = room.siteName ?? room.campusName { counts[site, default: 0] += 1 } }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// The campus of a site with the most rooms: where its free rooms are
    /// looked for first.
    ///
    /// - Parameter site: A name from ``sites``.
    /// - Returns: A name from ``campuses``, or `nil` when the site has no rooms.
    func mainCampus(inSite site: String) -> String? {
        var counts: [String: Int] = [:]
        for room in rooms where (room.siteName ?? room.campusName) == site {
            if let campus = room.campusName { counts[campus, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }
}

extension RoomAvailability {
    func load() async { await load(force: false) }
}

import Foundation

/// The order a campus's rooms are asked about.
///
/// Occupancy is one request per room, eight at a time, so on a large campus the
/// last room is asked about some twenty batches after the first. In the catalogue's
/// order that makes the first rooms listed whichever come first alphabetically.
/// In this order they are the ones the student is most likely looking for: the
/// buildings on the map in front of them, then the building of their next lecture,
/// then their own campus, then everything else.
nonisolated enum RelevanceOrder {
    /// Orders rooms by how likely they are to be wanted first.
    ///
    /// Within each group the rooms keep the order they were given in.
    ///
    /// - Parameters:
    ///   - rooms: The rooms to ask about.
    ///   - visible: The codes of the buildings in the map area on screen.
    ///   - nextLecture: The code of the building of the student's next lecture today.
    ///   - favourite: The student's favourite campus.
    /// - Returns: The same rooms, most wanted first.
    static func order(_ rooms: [Classroom], visible: Set<String>, nextLecture: String?,
                      favourite: String?) -> [Classroom] {
        func rank(_ room: Classroom) -> Int {
            if visible.contains(room.buildingCode) { return 0 }
            if let nextLecture, room.buildingCode == nextLecture { return 1 }
            if let favourite, room.campusName == favourite { return 2 }
            return 3
        }
        return rooms.enumerated()
            .map { (rank: rank($0.element), index: $0.offset, room: $0.element) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.room)
    }

    /// The building a lecture's room is in.
    ///
    /// - Parameters:
    ///   - names: What the timetable calls the room: the code on the door, its name.
    ///   - rooms: The catalogue.
    /// - Returns: The building's code, or `nil` when the catalogue has no such room.
    static func building(ofRoom names: [String?], in rooms: [Classroom]) -> String? {
        // The timetable writes "Aula B.3.2" where the catalogue has "B.3.2".
        let wanted = Set(names.compactMap { name -> String? in
            guard var text = name?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
            if text.hasPrefix("aula ") { text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            return text.isEmpty ? nil : text
        })
        guard !wanted.isEmpty else { return nil }
        return rooms.first { room in
            wanted.contains(room.id.lowercased())
                || (room.roomCode.map { wanted.contains($0.lowercased()) } ?? false)
        }?.buildingCode
    }
}

/// Keeps a list still while rows are arriving in it.
///
/// A sorted list that receives rows one batch at a time would move the rows the
/// student is reading each time. While rows arrive, or the list is being scrolled,
/// the rows already shown keep their places and new ones go below; once it is
/// quiet the list takes its sorted order, in one move.
nonisolated enum StableOrder {
    /// The order to show.
    ///
    /// - Parameters:
    ///   - shown: The ids on screen, in the order they are shown.
    ///   - sorted: The ids there are now, in the order they should end up in.
    ///   - settle: Whether the list may take its sorted order now.
    /// - Returns: The ids to show, in order. Always exactly the ids in `sorted`.
    static func merge<ID: Hashable>(shown: [ID], sorted: [ID], settle: Bool) -> [ID] {
        guard !settle, !shown.isEmpty else { return sorted }
        let present = Set(sorted)
        let kept = shown.filter(present.contains)
        let already = Set(kept)
        return kept + sorted.filter { !already.contains($0) }
    }
}

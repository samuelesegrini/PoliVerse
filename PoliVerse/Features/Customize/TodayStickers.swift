import SwiftUI

/// What sits on the right half beside the greeting and the date. With
/// nothing, the date takes the whole width.
nonisolated enum TodayAccessory: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Nothing, so the date takes the whole width.
    case none
    /// Stickers placed by hand.
    case stickers
    /// A few words in the Flavor's colour.
    case text
    /// Up to three photos in a small stack.
    case photos

    /// The accessory's identity, which is its raw value.
    var id: String { rawValue }

    /// What the accessory is called in Personalizza.
    var title: LocalizedStringKey {
        switch self {
        case .none: "Nessuno"
        case .stickers: "Sticker"
        case .text: "Testo"
        case .photos: "Foto"
        }
    }

    /// The accessory's SF Symbol.
    var systemImage: String {
        switch self {
        case .none: "rectangle"
        case .stickers: "face.smiling"
        case .text: "textformat"
        case .photos: "photo.on.rectangle.angled"
        }
    }
}

/// A sticker on the panel beside the date, placed by the student.
///
/// Positions are fractions of the panel, so the same look draws the same way
/// on a gallery card and at full size.
nonisolated struct PlacedSticker: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// What a sticker is: an emoji, or an image the keyboard handed over.
    nonisolated enum Content: Codable, Equatable, Hashable, Sendable {
        /// An emoji, drawn as text.
        case emoji(String)
        /// A sticker, Memoji or Genmoji from the keyboard, kept by ``StickerStore``.
        case image(String)
    }

    /// The sticker's identity, kept so a change reaches the right one.
    let id: UUID
    /// What the sticker is.
    var content: Content
    /// The centre, from 0 (left) to 1 (right).
    var x = 0.5
    /// The centre, from 0 (top) to 1 (bottom).
    var y = 0.5
    /// The side, as a fraction of the panel's height.
    var size = 0.5
    /// Degrees clockwise.
    var rotation = 0.0

    /// A sticker in the middle of the panel, unturned.
    ///
    /// - Parameters:
    ///   - id: Its identity; a fresh one by default.
    ///   - content: What the sticker is.
    init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }

    /// The range a sticker's size is clamped to.
    static let sizes = 0.2...0.9
    /// The range a sticker's turn is clamped to, in degrees.
    static let rotations = -40.0...40.0

    /// The same sticker kept inside the panel, at a size and turn that read.
    func clamped() -> PlacedSticker {
        var sticker = self
        sticker.x = x.clamped(to: 0...1)
        sticker.y = y.clamped(to: 0...1)
        sticker.size = size.clamped(to: Self.sizes)
        sticker.rotation = rotation.clamped(to: Self.rotations)
        return sticker
    }
}

/// Adding, changing and removing a look's stickers and photos.
nonisolated extension TodayStyle {
    /// Beyond this the panel is a pile, not an arrangement.
    static let maxStickers = 6

    /// Where new stickers land, in order: the middle first, then around it,
    /// each a little turned so a few together look placed by hand.
    private static let spots: [(x: Double, y: Double, rotation: Double)] = [
        (0.5, 0.5, 0), (0.25, 0.3, -12), (0.75, 0.7, 10),
        (0.75, 0.28, 8), (0.25, 0.72, -8), (0.5, 0.15, 4),
    ]

    /// Adds a sticker at the spot farthest from the others, earlier spots
    /// first on a tie, and shows the sticker panel. Returns nil when the
    /// panel is full.
    @discardableResult
    mutating func addSticker(_ content: PlacedSticker.Content, id: UUID = UUID()) -> PlacedSticker? {
        guard stickers.count < Self.maxStickers else { return nil }
        func room(_ spot: (x: Double, y: Double, rotation: Double)) -> Double {
            stickers.map { hypot($0.x - spot.x, $0.y - spot.y) }.min() ?? .infinity
        }
        var spot = Self.spots[0]
        for candidate in Self.spots.dropFirst() where room(candidate) > room(spot) {
            spot = candidate
        }
        var sticker = PlacedSticker(id: id, content: content)
        sticker.x = spot.x
        sticker.y = spot.y
        sticker.rotation = spot.rotation
        sticker.size = stickers.isEmpty ? 0.6 : 0.42
        stickers.append(sticker)
        accessory = .stickers
        return sticker
    }

    /// Changes one sticker and pulls it back inside the panel.
    ///
    /// - Parameters:
    ///   - id: Which sticker.
    ///   - change: What to change about it.
    mutating func updateSticker(_ id: UUID, _ change: (inout PlacedSticker) -> Void) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        change(&stickers[index])
        stickers[index] = stickers[index].clamped()
    }

    /// Takes one sticker off the panel.
    ///
    /// - Parameter id: Which sticker.
    mutating func removeSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
    }

    /// Beyond this the stack hides more than it shows.
    static let maxPhotos = 3

    /// Puts a stored photo on top of the stack, dropping the oldest when full,
    /// and shows the photos.
    mutating func addPhoto(_ id: String) {
        photoIDs.append(id)
        if photoIDs.count > Self.maxPhotos { photoIDs.removeFirst(photoIDs.count - Self.maxPhotos) }
        accessory = .photos
    }

    /// Takes one photo off the stack.
    ///
    /// - Parameter id: The photo's id in ``StickerStore``.
    mutating func removePhoto(_ id: String) {
        photoIDs.removeAll { $0 == id }
    }

    /// The stored images this look draws, stickers and photos, so the store
    /// keeps them.
    var storedImageIDs: Set<String> {
        Set(stickers.compactMap {
            if case .image(let id) = $0.content { id } else { nil }
        } + photoIDs)
    }
}

/// The images of keyboard stickers, one file each, outside the looks: a look
/// is a short string in the defaults and an image would not fit there.
nonisolated struct StickerStore: Sendable {
    /// The folder the images are kept in, one file each.
    let directory: URL

    /// The app's own store, under Application Support.
    static let shared = StickerStore(
        directory: URL.applicationSupportDirectory.appending(path: "TodayStickers", directoryHint: .isDirectory))

    /// Writes the image and returns the id a look refers to it by.
    func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try data.write(to: url(for: id), options: .atomic)
        return id
    }

    /// One stored image.
    ///
    /// - Parameter id: The id a look refers to it by.
    /// - Returns: The image's data, or `nil` when there is no such file.
    func data(for id: String) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    /// Deletes every image no saved look uses any more. A file that cannot be
    /// deleted is left for the next time, without stopping the others.
    func prune(keeping ids: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !ids.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Where one image lives, with the id stripped to letters, digits and dashes so a crafted one stays inside the folder.
    ///
    /// - Parameter id: The image's id.
    /// - Returns: Its file's URL.
    private func url(for id: String) -> URL {
        // Ids are ours, but a stored look is still outside input: keep a
        // crafted one inside the directory.
        let name = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appending(path: "\(name).sticker")
    }
}

/// Pulling a value into a range.
nonisolated extension Comparable {
    /// The value pulled into the range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

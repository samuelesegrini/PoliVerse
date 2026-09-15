import Foundation
import Testing
@testable import PoliVerse

/// Stickers beside the date: where they land, how far they can be pushed, and
/// the files their images are kept in.
@Suite("Today stickers")
struct TodayStickersTests {
    @Test("The first sticker turns the header into date and stickers, in the middle of the panel")
    func firstSticker() throws {
        var style = TodayStyle()
        #expect(style.header == .date)
        let addedSticker = style.addSticker(.emoji("🎓"))
        let sticker = try #require(addedSticker)
        #expect(style.header == .dateAndStickers)
        #expect(sticker.x == 0.5 && sticker.y == 0.5)
        #expect(style.stickers == [sticker])
    }

    @Test("Later stickers land in different places, and the panel holds a fixed number")
    func spreadAndLimit() {
        var style = TodayStyle()
        for index in 0..<TodayStyle.maxStickers {
            let added = style.addSticker(.emoji("\(index)"))
            #expect(added != nil)
        }
        let spots = Set(style.stickers.map { "\($0.x),\($0.y)" })
        #expect(spots.count == TodayStyle.maxStickers)
        let overflow = style.addSticker(.emoji("🚫"))
        #expect(overflow == nil)
        #expect(style.stickers.count == TodayStyle.maxStickers)
    }

    @Test("Moving, resizing and turning are kept inside the panel")
    func clamped() throws {
        var style = TodayStyle()
        let addedSticker = style.addSticker(.emoji("⭐️"))
        let sticker = try #require(addedSticker)
        style.updateSticker(sticker.id) {
            $0.x = 3
            $0.y = -1
            $0.size = 9
            $0.rotation = 400
        }
        let moved = try #require(style.stickers.first)
        #expect(moved.x == 1 && moved.y == 0)
        #expect(moved.size == PlacedSticker.sizes.upperBound)
        #expect(moved.rotation == 40)
    }

    @Test("A new sticker avoids one moved onto a free spot")
    func avoidsMoved() throws {
        var style = TodayStyle()
        let added = style.addSticker(.emoji("1"))
        let first = try #require(added)
        style.updateSticker(first.id) { $0.x = 0.25; $0.y = 0.3 }
        let second = style.addSticker(.emoji("2"))
        let next = try #require(second)
        #expect(!(next.x == 0.25 && next.y == 0.3))
    }

    @Test("Removing a sticker leaves the others; the images in use are listed for the store")
    func removeAndImages() throws {
        var style = TodayStyle()
        let addedEmoji = style.addSticker(.emoji("☕️"))
        let emoji = try #require(addedEmoji)
        _ = style.addSticker(.image("A"))
        _ = style.addSticker(.image("B"))
        style.removeSticker(emoji.id)
        #expect(style.stickers.count == 2)
        #expect(style.stickerImageIDs == ["A", "B"])
    }

    @Test("Stickers and the header round-trip through the stored string")
    func roundTrip() throws {
        var style = TodayStyle()
        _ = style.addSticker(.image("glyph"))
        _ = style.addSticker(.emoji("🧪"))
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.header == .dateAndStickers)
        #expect(restored.stickers == style.stickers)
    }

    @Test("The store saves an image, reads it back and forgets the ones no look uses")
    func store() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stickers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerStore(directory: directory)

        let kept = try store.save(Data([1, 2, 3]))
        let dropped = try store.save(Data([4, 5]))
        #expect(kept != dropped)
        #expect(store.data(for: kept) == Data([1, 2, 3]))

        store.prune(keeping: [kept])
        #expect(store.data(for: kept) != nil)
        #expect(store.data(for: dropped) == nil)
        #expect(store.data(for: "missing") == nil)
    }
}

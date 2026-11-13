#if DEBUG && os(iOS)
import Foundation
import Testing
import UIKit
@testable import PoliVerse

@Suite("Mappa della scheda aula: la foto del campus 3D")
@MainActor
struct RoomCampusStillTests {
    /// The still's pixels vary: the campus was drawn, not just the background.
    private func isDrawn(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        let length = CFDataGetLength(data)
        var seen = Set<UInt32>()
        var index = 0
        while index + 3 < length, seen.count < 64 {
            seen.insert(UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]))
            index += 4 * 997
        }
        return seen.count >= 32
    }

    @Test("L'Edificio 3 si disegna dalla scena del campus, di giorno e di notte, e poi si legge dal disco")
    func drawsBuilding() async throws {
        let folder = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
            .appending(path: "RoomCampusStills")
        try? FileManager.default.removeItem(at: folder)

        let clock = ContinuousClock()
        let started = clock.now
        let day = try #require(await RoomCampusStill.image(for: "MIA0103", dark: false))
        let firstDraw = started.duration(to: clock.now)
        let night = try #require(await RoomCampusStill.image(for: "MIA0103", dark: true))
        #expect(day.size == RoomCampusStill.size)
        #expect(isDrawn(day))
        #expect(isDrawn(night))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "MIA0103-giorno.png").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "MIA0103-notte.png").path(percentEncoded: false)))
        print("RoomCampusStill first draw: \(firstDraw), folder: \(folder.path(percentEncoded: false))")
    }

    @Test("Un edificio fuori dal campus 3D non ha la foto")
    func outsideCampus() async {
        #expect(!RoomCampusStill.canDraw("CRG0204"))
        #expect(await RoomCampusStill.image(for: "CRG0204", dark: false) == nil)
    }
}
#endif

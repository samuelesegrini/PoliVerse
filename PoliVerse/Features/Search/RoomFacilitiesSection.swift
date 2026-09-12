import SwiftUI

/// Equipment and software for one room, as list sections.
///
/// Silent while nothing is known and silent when the answer is "nothing
/// recorded", which is the case for most rooms — an empty "Dotazioni" header
/// on every screen would be noise standing in for information.
struct RoomFacilitiesSection: View {
    /// `idaula` — the same key the occupancy call takes. Passed rather than a
    /// whole `Classroom` so the free-rooms detail, which holds a schedule
    /// instead, can show the same sections.
    let roomID: String?
    @Environment(RoomFacilitiesService.self) private var facilities

    private var equipment: [RoomFacility] {
        roomID.flatMap { facilities.equipment[$0] } ?? []
    }

    private var software: [RoomFacility] {
        roomID.flatMap { facilities.software[$0] } ?? []
    }

    var body: some View {
        Group {
            if !equipment.isEmpty {
                Section("Dotazioni") {
                    ForEach(equipment) { item in
                        Label(item.name, systemImage: item.symbol)
                            .font(.subheadline)
                    }
                }
            }

            if !software.isEmpty {
                Section {
                    ForEach(software) { item in
                        Label(item.name, systemImage: "app")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Software")
                } footer: {
                    Text("Installato sulle postazioni dell'aula.")
                }
            }
        }
        .task { await facilities.load(id: roomID) }
    }
}

/// One room from the catalogue: where it is, what it holds, what it has.
struct ClassroomDetailView: View {
    let room: Classroom
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                LabeledContent("Capienza", value: "\(room.capacity) posti")
                if let accessible = room.accessibleSeats {
                    LabeledContent("Posti accessibili", value: String(accessible))
                }
                if let floor = room.floorName {
                    LabeledContent("Piano", value: floor)
                }
                if let building = room.buildingName {
                    LabeledContent("Edificio", value: building)
                }
                if let campus = room.campusName {
                    LabeledContent("Sede", value: campus)
                }
            }

            RoomDayView(room: room)

            FloorPlanView(room: room)

            RoomFacilitiesSection(roomID: room.occupancyID)

            if let address = room.address {
                Section {
                    Button {
                        openInMaps(address)
                    } label: {
                        Label(address, systemImage: "map")
                    }
                } footer: {
                    // Said once, here, rather than implied by a pin that would
                    // be in the wrong place.
                    Text("Il catalogo indica l'indirizzo dell'edificio, non la posizione esatta dell'aula.")
                }
            }
        }
        .navigationTitle(room.id)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps(_ address: String) {
        guard
            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "http://maps.apple.com/?q=\(encoded)")
        else { return }
        openURL(url)
    }
}

// MARK: - Previews

#Preview("Dettaglio aula") {
    ClassroomDetailView(room: MockData.classrooms()[0]).previewInNavigation()
}

#Preview("Dotazioni") {
    List { RoomFacilitiesSection(roomID: MockData.classrooms()[0].occupancyID) }
        .previewEnvironment()
}

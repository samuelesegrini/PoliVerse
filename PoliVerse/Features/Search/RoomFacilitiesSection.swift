import SwiftUI

/// Equipment and software for one room, as list sections.
///
/// Silent once the answer is known to be "nothing recorded", which is the case
/// for a good number of rooms — an empty "Dotazioni" header on every screen
/// would be noise standing in for information. Until then it shows a
/// placeholder, which is also what gives the fetch somewhere to live: a
/// `Group` hands its modifiers to each child, so a `.task` on a Group with no
/// children never runs. Attached to the conditional sections alone, the fetch
/// only ever started for rooms whose equipment was already known — so a room
/// that had not been warmed by the list's prefetch stayed empty for good, and
/// "Dotazioni" never appeared.
struct RoomFacilitiesSection: View {
    /// `idaula` — the same key the occupancy call takes. Passed rather than a
    /// whole `Classroom` so the free-rooms detail, which holds a schedule
    /// instead, can show the same sections.
    let roomID: String?
    /// The shared ``RoomFacilitiesModel``, from the environment.
    @Environment(RoomFacilitiesModel.self) private var facilities
    /// Whether the fetch has been tried for ``roomID``. Both endpoints
    /// failing leaves nothing loaded, and without this the placeholder would
    /// spin for as long as the screen was open.
    @State private var attempted = false

    /// The room's equipment, once fetched.
    private var equipment: [RoomFacility] {
        roomID.flatMap { facilities.equipment[$0] } ?? []
    }

    /// The software installed in the room. Empty for anything that is not a computer
    /// laboratory.
    private var software: [RoomFacility] {
        roomID.flatMap { facilities.software[$0] } ?? []
    }

    /// Whether the answer has arrived. A room with no id has nothing to ask
    /// about, so it counts as answered rather than perpetually loading.
    private var isLoaded: Bool {
        guard let roomID else { return true }
        return facilities.isLoaded(roomID)
    }

    /// The view's content.
    var body: some View {
        Group {
            if !isLoaded && !attempted {
                Section("Dotazioni") {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Carico…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    // On the row rather than the section: this is the view that
                    // is certain to be in the list, and it exists exactly while
                    // the answer is still missing.
                    .task(id: roomID) {
                        attempted = false
                        await facilities.load(id: roomID)
                        attempted = true
                    }
                }
                .lookRow()
            }

            if !equipment.isEmpty {
                Section("Dotazioni") {
                    ForEach(equipment) { item in
                        Label(item.name, systemImage: item.symbol)
                            .font(.subheadline)
                    }
                }
                .lookRow()
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
                .lookRow()
            }
        }
    }
}

/// One room from the catalogue: where it is, what it holds, what it has.
struct ClassroomDetailView: View {
    /// The room being shown.
    let room: Classroom
    /// Opens a link outside the app.
    @Environment(\.openURL) private var openURL

    /// The view's content.
    var body: some View {
        List {
            Section {
                PageHero(symbol: "door.left.hand.open", title: Text(verbatim: room.id), summary: room.locationLabel.isEmpty ? nil : Text(verbatim: room.locationLabel))
                    .listHeader()
            }
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
            .lookRow()

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
                .lookRow()
            }
        }
        .lookList()
        .navigationTitle(room.id)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Opens the building's address in Maps.
    ///
    /// - Parameter address: The address as the catalogue records it.
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
    ClassroomDetailView(room: Classroom.samples()[0]).previewInNavigation()
}

#Preview("Dotazioni") {
    List { RoomFacilitiesSection(roomID: Classroom.samples()[0].occupancyID) }
        .previewEnvironment()
}

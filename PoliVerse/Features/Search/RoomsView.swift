import SwiftUI

/// Browse and search the room catalogue.
struct RoomsView: View {
    @Environment(RoomsService.self) private var rooms
    @Environment(RoomFacilitiesService.self) private var facilities
    @Environment(FreeRoomsService.self) private var freeRooms

    @State private var query = ""
    @State private var campus: String?

    private var results: [Classroom] {
        rooms.rooms(matching: query, campus: campus)
    }

    /// Grouped by building so a long list stays navigable.
    private var grouped: [(building: String, rooms: [Classroom])] {
        Dictionary(grouping: results) { $0.buildingName ?? "Altro" }
            .map { (building: $0.key, rooms: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.building < $1.building }
    }

    var body: some View {
        List {
            Section {
                PageHero(symbol: "building.2", title: Text("Aule"), summary: Text("Tutte le aule del Politecnico"))
                    .listHeader()
            }
            Section {
                NavigationLink {
                    CampusMapView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mappa del campus")
                                .font(.subheadline.weight(.semibold))
                            Text("Edifici e aule sulla mappa, con le piante ufficiali.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "map").foregroundStyle(Theme.brand)
                    }
                }

                NavigationLink {
                    FreeRoomsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Aule libere")
                                .font(.subheadline.weight(.semibold))
                            Text("Fasce libere per giorno, ricavate dalle lezioni prenotate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(Theme.brand)
                    }
                }
            }
            .glassRow()

            if rooms.campuses.count > 1 {
                Section {
                    Picker("Sede", selection: $campus) {
                        Text("Tutte").tag(String?.none)
                        ForEach(rooms.campuses, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                }
                .glassRow()
            }

            ForEach(grouped, id: \.building) { group in
                Section {
                    ForEach(group.rooms) { room in
                        NavigationLink {
                            ClassroomDetailView(room: room)
                        } label: {
                            RoomRow(room: room)
                        }
                    }
                } header: {
                    Text(group.building)
                } footer: {
                    if let address = group.rooms.first?.address {
                        Text(address)
                    }
                }
                .glassRow()
            }
        }
        // Warms the equipment and occupancy of rows just off screen, so
        // opening one is instant rather than a spinner.
        .prefetching(results.map(\.id)) { ids in
            let wanted = results.filter { ids.contains($0.id) }
            facilities.prefetch(wanted)
            freeRooms.prefetch(wanted)
        }
        .glassList()
        .navigationTitle("Aule")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Sigla aula, edificio o sede")
        .overlay {
            if rooms.isLoading && rooms.rooms.isEmpty {
                ProgressView()
            } else if results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if rooms.rooms.isEmpty, let message = rooms.errorMessage {
                ContentUnavailableView("Catalogo non disponibile",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
        .task { await rooms.load() }
        .refreshable { await rooms.load(force: true) }
    }

}

private struct RoomRow: View {
    let room: Classroom

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.id)
                    .font(.subheadline.weight(.semibold))
                    .monospaced()

                HStack(spacing: 8) {
                    Label("\(room.capacity) posti", systemImage: "person.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let floor = room.floorName {
                        Label(floor, systemImage: "stairs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let accessible = room.accessibleSeats {
                        Label("\(accessible)", systemImage: "figure.roll")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("Catalogo aule") {
    RoomsView().previewInNavigation()
}

#Preview("Componente · Riga aula") {
    List {
        ForEach(MockData.classrooms()) { RoomRow(room: $0) }
    }
    .previewEnvironment()
}

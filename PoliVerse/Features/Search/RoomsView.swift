import SwiftUI

/// Browse and search the room catalogue.
struct RoomsView: View {
    @Environment(RoomsService.self) private var rooms
    @Environment(\.openURL) private var openURL

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
            if !rooms.knowsOccupancy {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Disponibilità non disponibile")
                                .font(.subheadline.weight(.semibold))
                            Text("Il Politecnico non espone pubblicamente quali aule siano libere: i servizi che lo sanno sono raggiungibili solo dalla rete d'ateneo. Qui trovi l'elenco completo con edificio, piano e capienza.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    }
                }
            }

            if rooms.campuses.count > 1 {
                Section {
                    Picker("Sede", selection: $campus) {
                        Text("Tutte").tag(String?.none)
                        ForEach(rooms.campuses, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                }
            }

            ForEach(grouped, id: \.building) { group in
                Section {
                    ForEach(group.rooms) { room in
                        RoomRow(room: room) {
                            openInMaps(room)
                        }
                    }
                } header: {
                    Text(group.building)
                } footer: {
                    if let address = group.rooms.first?.address {
                        Text(address)
                    }
                }
            }
        }
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

    /// The catalogue has street addresses but no coordinates, so hand the
    /// address to Maps rather than pretending to a precise pin.
    private func openInMaps(_ room: Classroom) {
        guard
            let address = room.address,
            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "http://maps.apple.com/?q=\(encoded)")
        else { return }
        openURL(url)
    }
}

private struct RoomRow: View {
    let room: Classroom
    let onOpenMap: () -> Void

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

            if room.address != nil {
                Button(action: onOpenMap) {
                    Image(systemName: "map")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Apri \(room.id) in Mappe")
            }
        }
        .padding(.vertical, 2)
    }
}

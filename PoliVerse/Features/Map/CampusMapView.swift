import MapKit
import SwiftUI

/// The campus map: buildings as pins, drilling into rooms.
///
/// MapKit draws the city; we add only what the Politecnico actually knows —
/// a coordinate per building. The public geojson's outlines are generated
/// ellipses and bounding boxes rather than footprints, so nothing is drawn
/// from them. See ``BuildingLocation``.
struct CampusMapView: View {
    @Environment(CampusMapService.self) private var map
    @Environment(RoomsService.self) private var rooms

    @State private var campus: String?
    /// Opens on a campus rather than `.automatic`, which with no pins yet is
    /// the whole world, then jumps once they arrive.
    @State private var position: MapCameraPosition = .region(CampusRegions.region(for: nil))
    @State private var selected: MapPin?
    /// The campus the camera last framed; nil before any framing.
    @State private var framedCampus: String??
    @State private var loadingAvailability = false

    var body: some View {
        Map(position: $position, selection: Binding(
            get: { selected?.id },
            // Tapping the same pin again clears it, so the sheet can be
            // dismissed from the map as well as from the sheet.
            set: { id in selected = map.pins.first { $0.id == id } }
        )) {
            ForEach(map.pins) { pin in
                Marker(pin.name, systemImage: "building.2.fill", coordinate: pin.coordinate)
                    .tint(colour(for: pin))
                    .tag(pin.id)
            }
        }
        // Pins are handed over a few at a time, so each batch fades in rather
        // than the campus appearing in one step.
        .animation(.easeOut(duration: 0.25), value: map.pins.count)
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .top) { controls }
        .overlay(alignment: .bottom) { legend }
        .navigationTitle("Mappa")
        .navigationBarTitleDisplayMode(.inline)
        // The map is drawn at once; pins arrive as they are placed, and the
        // camera frames them the first time there are any.
        .task { await map.load(campus: campus) }
        // Framed once per campus, as soon as its pins are placed — not on
        // every re-placement, which would pull the camera from under a pan.
        // Off the full placement rather than the pins revealed so far, so the
        // camera frames the campus and not its first four buildings.
        .onChange(of: map.placed.count) { _, count in
            guard count > 0, framedCampus != .some(campus) else { return }
            framedCampus = campus
            recentre()
        }
        .onAppear {
            // Pins kept from an earlier visit: open on them, not on Milano.
            if let region = map.region {
                position = .region(region)
                framedCampus = campus
            }
        }
        .sheet(item: $selected) { pin in
            NavigationStack { BuildingSheet(pin: pin) }
                .presentationDetents([.medium, .large])
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if map.campuses.count > 1 {
                Picker("Sede", selection: $campus) {
                    Text("Tutte").tag(String?.none)
                    ForEach(map.campuses, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    loadingAvailability = true
                    await map.loadAvailability(campus: campus)
                    loadingAvailability = false
                }
            } label: {
                Label(
                    map.showsAvailability ? "Aggiorna disponibilità" : "Mostra libere ora",
                    systemImage: loadingAvailability ? "clock" : "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(loadingAvailability || map.placed.isEmpty)
        }
        .padding(12)
        .background(.bar)
        .onChange(of: campus) { _, _ in
            // The new campus's city at once; its pins frame it when placed.
            withAnimation { position = .region(CampusRegions.region(for: campus)) }
            Task { await map.load(campus: campus) }
        }
    }

    @ViewBuilder
    private var legend: some View {
        if map.showsAvailability {
            HStack(spacing: 14) {
                swatch(.green, "molte")
                swatch(.orange, "alcune")
                swatch(.red, "poche")
            }
            .font(.caption2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar, in: .capsule)
            .padding(.bottom, 12)
        } else if map.isPlacing || (map.isLoading && map.pins.isEmpty) {
            Label("Carico gli edifici…", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.bar, in: .capsule)
                .padding(.bottom, 12)
                .transition(.opacity)
        } else if loadingAvailability {
            // One request per room, so it is worth saying that out loud rather
            // than leaving a button looking stuck.
            Label("Controllo aula per aula…", systemImage: "clock")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.bar, in: .capsule)
                .padding(.bottom, 12)
        }
    }

    private func swatch(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func colour(for pin: MapPin) -> Color {
        switch pin.availability {
        case .many: .green
        case .some: .orange
        case .few: .red
        case .unknown: Theme.brand
        }
    }

    private func recentre() {
        guard let region = map.region else { return }
        withAnimation { position = .region(region) }
    }
}

/// What is in one building, reached by tapping its pin.
private struct BuildingSheet: View {
    let pin: MapPin
    @Environment(CampusMapService.self) private var map
    @Environment(\.dismiss) private var dismiss

    private var rooms: [Classroom] { map.rooms(in: pin.id) }

    var body: some View {
        List {
            Section {
                LabeledContent("Aule", value: String(rooms.count))
                LabeledContent("Posti", value: String(rooms.reduce(0) { $0 + $1.capacity }))
                if let address = rooms.first?.address {
                    LabeledContent("Indirizzo", value: address)
                }
            } footer: {
                if pin.freeRooms != nil { Text(pin.label) }
            }

            ForEach(byFloor, id: \.floor) { group in
                Section(group.floor) {
                    ForEach(group.rooms) { room in
                        NavigationLink {
                            ClassroomDetailView(room: room)
                        } label: {
                            HStack {
                                Text(room.id).font(.subheadline.weight(.medium)).monospaced()
                                Spacer()
                                Text("\(room.capacity) posti")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(pin.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    private var byFloor: [(floor: String, rooms: [Classroom])] {
        Dictionary(grouping: rooms) { $0.floorName ?? "Piano —" }
            .map { (floor: $0.key, rooms: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.floor < $1.floor }
    }
}

// MARK: - Previews

#Preview("Mappa campus") {
    CampusMapView().previewInNavigation()
}

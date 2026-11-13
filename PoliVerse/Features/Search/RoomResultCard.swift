#if DEBUG && os(iOS)
import SwiftUI

/// A room as Cerca's best match, in the new interface (the "Cerca · Un'aula" canvas of
/// 13 November 2026).
///
/// While the keyboard is up it is a compact card (board 1): a thumbnail of the building
/// with the room pinned, the room's code, where it is, whether it is free, and Indicazioni.
/// When the keyboard goes down — the search is sent, the list is scrolled or the card is
/// tapped — the same card opens into the room's card (boards 2 and 3): the building from
/// above, or the room's photo, or a drawing of a classroom when there is none; the status
/// with a bar of the free time left; seats; Indicazioni and Dettagli; then the rooms free
/// now in the same building. Opening the keyboard again folds it back.
struct RoomResultCard: View {
    let room: Classroom
    /// Whether the card is open: the keyboard is down.
    let expanded: Bool
    /// Closes the keyboard, which opens the card.
    let open: () -> Void
    /// Keeps the search among the recent ones, as any result that is followed does.
    let remember: () -> Void

    @Environment(FreeRoomsModel.self) private var aule
    @Environment(CampusMapModel.self) private var campusMap
    @Environment(RoomsModel.self) private var rooms
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    @Namespace private var morph
    @Namespace private var zoom

    @State private var bookings: [RoomBooking]?
    @State private var readingBookings = true
    @State private var photo: RoomPhotoState = .unknown
    @State private var mapImage: UIImage?
    @State private var mode: RoomHeroMode = .map
    @State private var showsPhoto = false
    @State private var showsMap = false
    @State private var showsDetails = false
    @State private var nearby: [NearbyRoom] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let status = RoomStatusText.make(bookings: bookings, isLoading: readingBookings,
                                             now: context.date, day: aule.teachingDay)
            VStack(alignment: .leading, spacing: 14) {
                if expanded {
                    fullCard(status)
                } else {
                    compactCard(status)
                }
                if expanded, !nearby.isEmpty {
                    nearbySection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .fullScreenCover(isPresented: $showsPhoto) {
                if let image = photo.image {
                    RoomPhotoViewer(room: room, image: image, status: status, directions: directions)
                        .navigationTransition(.zoom(sourceID: "photo", in: zoom))
                }
            }
        }
        .animation(.spring(duration: 0.35), value: expanded)
        .animation(.snappy, value: nearby.map(\.id))
        .navigationDestination(isPresented: $showsMap) { RoomDestination(room: room) }
        .navigationDestination(isPresented: $showsDetails) { ClassroomDetailView(room: room) }
        .task(id: room.id) { await load() }
        .task(id: "\(room.buildingCode)-\(scheme == .dark)") { if onCampusMap { await loadMap() } }
        .task(id: expanded ? room.id : "") {
            guard expanded else { return }
            await loadNearby()
        }
        .onChange(of: room.id, initial: true) {
            mode = onCampusMap ? .map : .room
            nearby = []
        }
    }

    // MARK: - Compact (keyboard up)

    private func compactCard(_ status: RoomStatusText) -> some View {
        VStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 14) {
                    thumbnail
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                        .matchedGeometryEffect(id: "hero", in: morph)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(room.id)
                            .font(.system(size: 22, weight: .bold))
                            .kerning(-0.3)
                            .matchedGeometryEffect(id: "title", in: morph)
                        Text(RoomWording.location(of: room))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .matchedGeometryEffect(id: "subtitle", in: morph)
                        Text(status.compact)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(status.tone.colour)
                            .padding(.top, 2)
                            .matchedGeometryEffect(id: "status", in: morph)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Apre la scheda dell'aula"))
            DirectionsButton(height: 40, action: directions)
                .matchedGeometryEffect(id: "directions", in: morph)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.roomCard)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .matchedGeometryEffect(id: "card", in: morph)
        }
        .accessibilityIdentifier("search-room-card")
    }

    /// The thumbnail: the building with the room pinned; the room's photo instead when the
    /// room is named after someone, whose name says nothing about where it is.
    @ViewBuilder
    private var thumbnail: some View {
        if (RoomNaming.isName(room.id) || !onCampusMap), let image = photo.image {
            Image(uiImage: image).resizable().scaledToFill()
        } else if onCampusMap {
            RoomMapPicture(image: mapImage, pinSize: 28)
        } else if photo == .absent {
            ClassroomSketch()
        } else {
            Color(.secondarySystemFill)
        }
    }

    // MARK: - Full (keyboard down)

    private func fullCard(_ status: RoomStatusText) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .frame(height: 193)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25))
                .padding([.horizontal, .top], 3)
                .matchedGeometryEffect(id: "hero", in: morph)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.id)
                        .font(.system(size: 34, weight: .bold))
                        .kerning(-0.5)
                        .matchedGeometryEffect(id: "title", in: morph)
                    Text(RoomWording.location(of: room))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .matchedGeometryEffect(id: "subtitle", in: morph)
                }
                statusBlock(status)
                    .matchedGeometryEffect(id: "status", in: morph)
                facts
                HStack(spacing: 10) {
                    DirectionsButton(height: 50, action: directions)
                        .matchedGeometryEffect(id: "directions", in: morph)
                    Button { showsDetails = true; remember() } label: {
                        Text("Dettagli")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 20)
                            .frame(height: 50)
                            .background(.tint.opacity(0.12), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search-room-details")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.roomCard)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .matchedGeometryEffect(id: "card", in: morph)
        }
        .accessibilityIdentifier("search-room-card")
    }

    /// The picture at the top: the map, the photo or the drawing, the switch between them,
    /// and the fade into the card.
    private var hero: some View {
        ZStack(alignment: .top) {
            Group {
                switch mode {
                case .map:
                    RoomMapPicture(image: mapImage)
                        .contentShape(.rect)
                        .onTapGesture { remember(); showsMap = true }
                        .accessibilityElement()
                        .accessibilityLabel(Text("L'\(room.buildingName ?? "edificio") nella mappa, con l'aula \(room.id) segnata"))
                        .accessibilityHint(Text("Apre la mappa del campus"))
                        .accessibilityAddTraits(.isButton)
                case .room:
                    roomPicture
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            VStack {
                Spacer()
                EasedFade(colour: .roomCard).frame(height: 56)
            }

            if onCampusMap, photo != .unknown {
                RoomHeroSwitch(mode: $mode, roomTitle: photo == .absent ? "Aula" : "Foto")
                    .padding(.top, 12)
                    .transition(.opacity)
            }
            if mode == .room, photo.image != nil {
                HStack {
                    Spacer()
                    Button { showsPhoto = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Mostra la foto a schermo intero"))
                }
                .padding(.top, 13)
                .padding(.trailing, 12)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: photo)
        .animation(.snappy, value: mode)
    }

    @ViewBuilder
    private var roomPicture: some View {
        switch photo {
        case .photo(_, let image?):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(.rect)
                .onTapGesture { showsPhoto = true }
                .matchedTransitionSource(id: "photo", in: zoom)
                .accessibilityLabel(Text("Foto dell'aula \(room.id)"))
                .accessibilityAddTraits([.isImage, .isButton])
        case .photo(_, nil):
            ZStack {
                Color(.secondarySystemFill)
                ProgressView()
            }
        case .absent:
            ClassroomSketch()
        case .unknown:
            Color(.secondarySystemFill)
        }
    }

    /// "Libera ora fino alle 14:15", the bar of the free time left, and what comes next.
    private func statusBlock(_ status: RoomStatusText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(status.headline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(status.tone.colour)
                if let until = status.until {
                    Text(until).font(.system(size: 15)).foregroundStyle(.secondary)
                }
            }
            if let remaining = status.remaining {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(status.tone.colour)
                                .frame(width: max(6, proxy.size.width * remaining))
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text(status.detail ?? status.compact))
            }
            if let detail = status.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(status.remaining != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seats, and the accessible ones where there are any.
    private var facts: some View {
        HStack(spacing: 18) {
            Label("\(room.capacity) posti", systemImage: "person.2")
            if let accessible = room.accessibleSeats, accessible > 0 {
                Label("\(accessible) accessibili", systemImage: "figure.roll")
            }
        }
        .labelStyle(FactLabelStyle())
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
    }

    // MARK: - Free rooms nearby

    /// A free room in the same building.
    struct NearbyRoom: Identifiable {
        let room: Classroom
        /// "Libera fino alle 13:15".
        let status: String
        /// "stesso piano", "piano terra".
        let place: String
        var id: String { room.id }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Libere ora vicino")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(nearby) { item in
                    NavigationLink { RoomDestination(room: item.room) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.room.id).font(.system(size: 17, weight: .semibold))
                                Text("\(Text(item.status).foregroundStyle(Color.freeRoom).fontWeight(.semibold)), \(item.place)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { remember() })
                    if item.id != nearby.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.roomCard, in: .rect(cornerRadius: 22))
        }
    }

    // MARK: - Loading

    private func load() async {
        bookings = nil
        readingBookings = true
        photo = .unknown
        async let photoRead: Void = loadPhoto()
        bookings = await aule.bookings(for: room)
        readingBookings = false
        await photoRead
    }

    /// Whether the room has a photo, then the photo itself. A room the index has not
    /// answered for stays on the map with no switch.
    private func loadPhoto() async {
        let store = RoomPhotos.shared
        let id = await store.photoID(for: room.roomCode)
        guard let id else {
            let known = await store.photoIDIfKnown(for: room.roomCode).known
            if known || room.roomCode == nil { photo = .absent }
            return
        }
        photo = .photo(id: id, image: nil)
        guard let data = await store.imageData(for: id), let image = UIImage(data: data) else { return }
        let prepared = await image.byPreparingForDisplay() ?? image
        guard case .photo(id, _) = photo else { return }
        photo = .photo(id: id, image: prepared)
    }

    /// The building in the app's 3D campus: drawn once per building and look, then read from disk.
    private func loadMap() async {
        mapImage = nil
        let image = await RoomCampusStill.image(for: room.buildingCode, dark: scheme == .dark)
        withAnimation(.easeOut(duration: 0.2)) { mapImage = image }
    }

    /// Whether the room's building is in the 3D campus, so the card can show it on the map.
    private var onCampusMap: Bool { RoomCampusStill.canDraw(room.buildingCode) }

    /// Up to three rooms of the same building that are free now, the same floor first.
    private func loadNearby() async {
        let here = room
        let candidates = Array(rooms.rooms
            .filter { $0.buildingCode == here.buildingCode && $0.id != here.id && $0.occupancyID != nil }
            .sorted { ($0.floorCode == here.floorCode ? 0 : 1, $0.id) < ($1.floorCode == here.floorCode ? 0 : 1, $1.id) }
            .prefix(8))
        guard !candidates.isEmpty else { nearby = []; return }
        let aule = aule
        var fetched: [String: [RoomBooking]?] = [:]
        await withTaskGroup(of: (String, [RoomBooking]?).self) { group in
            for candidate in candidates {
                group.addTask { (candidate.id, await aule.bookings(for: candidate)) }
            }
            for await (id, bookings) in group { fetched[id] = bookings }
        }
        guard !Task.isCancelled else { return }
        let now = Date.now, day = aule.teachingDay
        nearby = Array(candidates.compactMap { candidate -> NearbyRoom? in
            let status = RoomStatusText.make(bookings: fetched[candidate.id] ?? nil, now: now, day: day)
            guard status.tone == .free else { return nil }
            let place = candidate.floorCode == here.floorCode
                ? String(localized: "stesso piano")
                : RoomWording.floor(name: candidate.floorName, code: candidate.floorCode) ?? candidate.buildingName ?? ""
            return NearbyRoom(room: candidate, status: status.compact, place: place)
        }.prefix(3))
    }

    /// Walking directions to the room's building in Maps, as Cerca's other room actions.
    private func directions() {
        remember()
        Task {
            guard let point = await campusMap.coordinate(of: room.buildingCode),
                  let url = URL(string: "http://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)&dirflg=w")
            else { return }
            openURL(url)
        }
    }
}

/// A fact's symbol and its words six points apart.
private struct FactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}
#endif

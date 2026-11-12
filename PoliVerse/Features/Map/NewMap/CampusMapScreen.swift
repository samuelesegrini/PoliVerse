#if DEBUG && os(iOS)
import MapKit
import SwiftUI

// The new map (``BetaFeature/newMap``): the 3D campus full screen and one glass panel at the
// bottom that holds everything a student asks of it — find a room, see the next lesson, pick a
// floor, tell free rooms from busy ones. The design and the reasons behind it are in the
// "Mappa PoliVerse · wireframe" canvas of 12 November 2026.
//
// Debug builds only, like the 3D scene it draws (``Trifoglio3DScene``).

/// The new map screen.
struct CampusMapScreen: View {
    /// The room to open on, from Cerca or the rooms list; `nil` opens on the campus.
    var target: Classroom?

    /// The scene and its animations.
    @State private var scene = Trifoglio3DScene()
    /// The bookings of the rooms in the buildings visited, read through ``FreeRoomsModel``.
    @State private var occupancy = MapOccupancy()
    /// Whether the panel is pulled up.
    @State private var expanded = false
    /// Whether the panel is searching.
    @State private var searching = false
    /// What is typed in the search field.
    @State private var query = ""
    /// Whether a floor's list shows only the free rooms.
    @State private var onlyFree = false
    /// The room whose full page is open in a sheet.
    @State private var details: Classroom?
    /// Whether Aule libere is open in a sheet.
    @State private var showsFreeRooms = false
    /// Whether the search field has the keyboard.
    @FocusState private var searchFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(RoomsModel.self) private var rooms
    @Environment(FreeRoomsModel.self) private var aule
    @Environment(AgendaModel.self) private var agenda
    @Environment(CampusMapModel.self) private var map

    /// Whether the night palette is on: the new map always follows the system.
    private var dark: Bool { colorScheme == .dark }

    /// Whether a room can be shown on this map: its building is modelled.
    ///
    /// - Parameter room: The room.
    /// - Returns: `true` when the 3D campus has the room's building.
    static func canShow(_ room: Classroom) -> Bool {
        Trifoglio3DScene.buildings.contains(room.buildingCode)
    }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Trifoglio3DStage(scene: scene, dark: dark)
                    .ignoresSafeArea()
                TimelineView(.everyMinute) { context in
                    panel(now: context.date, maxHeight: proxy.size.height * (expanded || searching ? 0.8 : 0.5))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .topLeading) { backButton.padding(.leading, 16).padding(.top, 4) }
            .overlay(alignment: .topTrailing) { floorColumn.padding(.trailing, 16).padding(.top, 56) }
        }
        .background(dark ? Color(red: 0.05, green: 0.06, blue: 0.09) : Color(red: 0.91, green: 0.93, blue: 0.95))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("newmap")
        .sheet(item: $details) { room in
            NavigationStack {
                ClassroomDetailView(room: room)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fine") { details = nil } }
                    }
            }
        }
        .sheet(isPresented: $showsFreeRooms) {
            NavigationStack {
                FreeRoomsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fine") { showsFreeRooms = false } }
                    }
            }
        }
        .task { await rooms.load() }
        .task {
            // Once the campus is drawn, straight to the room the map was opened for.
            guard let target else { return }
            while scene.firstFrame == nil {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let level = MapTargets.level(of: target, plans: scene.plans) {
                await scene.go(to: level)
            }
        }
        .onChange(of: scene.level) { _, level in
            if case .campus = level { return }
            // The building's rooms, the floor on screen first.
            let csie = scene.csie
            let floor = currentFloor
            let wanted = rooms.rooms
                .filter { $0.buildingCode == csie }
                .sorted { ($0.floorCode == floor ? 0 : 1) < ($1.floorCode == floor ? 0 : 1) }
            Task { await occupancy.load(wanted, from: aule) }
        }
    }

    // MARK: - Over the scene

    /// Goes up one level: from a room to its floor, from a floor to its building, from a
    /// building to the campus, and from the campus back to where the map was opened from.
    private var backButton: some View {
        Button {
            Task { await goUp() }
        } label: {
            if let parent = parentTitle {
                Label(parent, systemImage: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel(parentTitle.map { Text("Torna a \($0)") } ?? Text("Indietro"))
        .accessibilityIdentifier("newmap-back")
    }

    /// The level the back button goes to, named; `nil` on the campus, where it leaves the map.
    private var parentTitle: String? {
        switch scene.level {
        case .campus: nil
        case .building: String(localized: "Campus")
        case .floor: MapNames.building(scene.plan, csie: scene.csie)
        case .room(let csip, _): MapNames.floor(csip)
        case .inside(_, let csiv): String(localized: "Aula \(sigla(csiv))")
        }
    }

    /// One level up. See ``backButton``.
    private func goUp() async {
        switch scene.level {
        case .campus: dismiss()
        case .building: await scene.go(to: .campus)
        case .floor: await scene.go(to: .building(scene.csie))
        case .room(let csip, _): await scene.go(to: .floor(csip))
        case .inside(let csip, let csiv): await scene.go(to: .room(floor: csip, room: csiv))
        }
    }

    /// The building's floors, top first, as a lift's buttons: shown from the building down.
    @ViewBuilder
    private var floorColumn: some View {
        if scene.level != .campus, let plan = scene.plan, !plan.piani.isEmpty {
            VStack(spacing: 2) {
                ForEach(plan.piani.reversed()) { floor in
                    let chosen = currentFloor == floor.csip
                    Button {
                        Task { await scene.go(to: .floor(floor.csip)) }
                    } label: {
                        Text(MapNames.floorShort(floor.csip))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(chosen ? Theme.onAccent : Color.primary)
                            .background { if chosen { Circle().fill(.tint) } }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(MapNames.floor(floor.csip)))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Piani")
            .accessibilityIdentifier("newmap-floors")
        }
    }

    // MARK: - The panel

    /// The glass panel at the bottom: a header that stays, and a body that scrolls only when
    /// it does not fit.
    ///
    /// - Parameters:
    ///   - now: The moment the statuses are read against.
    ///   - maxHeight: The tallest the panel may be.
    private func panel(now: Date, maxHeight: CGFloat) -> some View {
        CappedHeight(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 12) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
                    .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                        withAnimation(.snappy) { expanded = value.translation.height < 0 }
                    })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(expanded ? Text("Riduci il pannello") : Text("Espandi il pannello"))

                if let failure = scene.failure {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                }
                header(now: now)
                ViewThatFits(in: .vertical) {
                    bodyContent(now: now)
                    ScrollView {
                        bodyContent(now: now)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .animation(.snappy, value: scene.level)
        .accessibilityIdentifier("newmap-panel")
    }

    /// The panel's header: the search field on the campus, else where the camera is.
    @ViewBuilder
    private func header(now: Date) -> some View {
        if searching {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Aule ed edifici", text: $query)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("newmap-search-field")
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.secondary.opacity(0.14), in: .capsule)
                Button {
                    endSearch()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Chiudi la ricerca")
            }
        } else {
            switch scene.level {
            case .campus:
                Button {
                    searching = true
                    searchFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Cerca aule ed edifici")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.secondary.opacity(0.14), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newmap-search")
            case .building(let csie):
                titleRow(MapNames.building(scene.plans[csie], csie: csie),
                         subtitle: buildingSubtitle(csie, now: now))
            case .floor(let csip):
                titleRow(MapNames.floor(csip), subtitle: floorSubtitle(csip, now: now))
            case .room(let csip, let csiv), .inside(let csip, let csiv):
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(MapNames.building(scene.plan, csie: scene.csie)) › \(MapNames.floor(csip))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    titleRow(String(localized: "Aula \(sigla(csiv))"), subtitle: nil, large: true)
                    statusLine(classroom(csiv), now: now)
                }
            }
        }
    }

    /// A title, what it holds, and the button that closes back to the campus.
    private func titleRow(_ title: String, subtitle: String?, large: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(large ? .title.bold() : .title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                Task { await scene.go(to: .campus) }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.16), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Torna al campus")
        }
    }

    /// The panel's body for where the camera is.
    @ViewBuilder
    private func bodyContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if searching {
                searchResults(now: now)
            } else {
                switch scene.level {
                case .campus: campusBody
                case .building(let csie): buildingBody(csie, now: now)
                case .floor(let csip): floorBody(csip, now: now)
                case .room(let csip, let csiv), .inside(let csip, let csiv): roomBody(floor: csip, room: csiv, now: now)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Campus

    /// The lesson to go to, the way to the free rooms, and the modelled buildings.
    @ViewBuilder
    private var campusBody: some View {
        if let next = CurrentClass.forAccessory(from: agenda.events(on: .now), now: .now) {
            nextClassCard(next)
        }
        Button {
            showsFreeRooms = true
        } label: {
            Label("Aule libere", systemImage: "checkmark.circle")
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("newmap-free-rooms")

        VStack(alignment: .leading, spacing: 0) {
            Text("Edifici")
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(modelledBuildings, id: \.self) { csie in
                Button {
                    Task { await scene.go(to: .building(csie)) }
                } label: {
                    row(title: MapNames.building(scene.plans[csie], csie: csie),
                        detail: scene.plans[csie]?.nome, trailing: nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The modelled buildings with a plan, by number.
    private var modelledBuildings: [String] {
        Trifoglio3DScene.buildings
            .filter { scene.plans[$0] != nil }
            .sorted { left, right in
                let a = scene.plans[left]?.numero ?? left
                let b = scene.plans[right]?.numero ?? right
                return a.localizedStandardCompare(b) == .orderedAscending
            }
    }

    /// The lesson in progress or the next today, with the way there.
    private func nextClassCard(_ next: CurrentClass) -> some View {
        let room = RelevanceOrder.room(named: [next.event.roomAcronym, next.event.room], in: rooms.rooms)
        let level = room.flatMap { MapTargets.level(of: $0, plans: scene.plans) }
        let time = next.event.start.formatted(.dateTime.hour().minute())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: next.event.kind == .exam ? "pencil.and.list.clipboard" : "person.bubble")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text([next.isOngoing ? String(localized: "Adesso") : String(localized: "Prossima"),
                          String(localized: "Alle \(time)"), next.event.roomLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                if let room {
                    Button {
                        directions(to: room.buildingCode)
                    } label: {
                        Label("Indicazioni", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                if let level {
                    Button {
                        Task { await scene.go(to: level) }
                    } label: {
                        Text("Mostra aula").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("newmap-show-next")
                }
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 22))
    }

    // MARK: Building

    /// The way to the building and its floors, each with how many rooms are free.
    @ViewBuilder
    private func buildingBody(_ csie: String, now: Date) -> some View {
        Button {
            directions(to: csie)
        } label: {
            Label("Indicazioni", systemImage: "figure.walk").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)

        VStack(spacing: 0) {
            ForEach((scene.plans[csie]?.piani ?? []).reversed()) { floor in
                Button {
                    Task { await scene.go(to: .floor(floor.csip)) }
                } label: {
                    row(title: MapNames.floor(floor.csip), detail: nil,
                        trailing: countLabel(floor.aule.map(\.csiv), now: now))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Floor

    /// The floor's rooms with their status, all or only the free ones.
    @ViewBuilder
    private func floorBody(_ csip: String, now: Date) -> some View {
        Picker("Mostra", selection: $onlyFree) {
            Text("Tutte").tag(false)
            Text("Libere ora").tag(true)
        }
        .pickerStyle(.segmented)

        let all = (scene.plan?.piani.first { $0.csip == csip }?.aule ?? [])
            .sorted { $0.sigla.localizedStandardCompare($1.sigla) == .orderedAscending }
        let shown = onlyFree ? all.filter { status(of: classroom($0.csiv), now: now).isFree } : all
        VStack(spacing: 0) {
            ForEach(shown) { room in
                Button {
                    Task { await scene.go(to: .room(floor: csip, room: room.csiv)) }
                } label: {
                    row(title: room.sigla, detail: room.posti.map { String(localized: "\($0) posti") },
                        trailing: AnyView(statusTag(status(of: classroom(room.csiv), now: now), now: now)))
                }
                .buttonStyle(.plain)
            }
            if shown.isEmpty {
                Text(onlyFree ? "Nessuna aula libera ora su questo piano." : "Nessuna aula su questo piano.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: Room

    /// What to do with the room, its day, and what it has.
    @ViewBuilder
    private func roomBody(floor csip: String, room csiv: String, now: Date) -> some View {
        let room = classroom(csiv)
        HStack(spacing: 8) {
            Button {
                directions(to: scene.csie)
            } label: {
                Label("Indicazioni", systemImage: "figure.walk").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            if scene.interior(csiv) != nil {
                if case .inside = scene.level {
                    Button("Esci") { Task { await scene.go(to: .room(floor: csip, room: csiv)) } }
                        .buttonStyle(.glass)
                } else {
                    Button("Entra") { Task { await scene.go(to: .inside(floor: csip, room: csiv)) } }
                        .buttonStyle(.glass)
                }
            }
            if let room {
                Button("Dettagli") { details = room }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)

        if let bookings = occupancy.bookings(of: room) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Oggi").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                OccupancyTimeline(bookings: bookings, day: aule.teachingDay)
            }
        }
        let seats = scene.plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.posti ?? room?.capacity
        let facts = [seats.map { String(localized: "\($0) posti") },
                     room?.accessibleSeats.map { String(localized: "\($0) posti accessibili") }]
            .compactMap { $0 }
        if !facts.isEmpty {
            Text(facts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Search

    /// The rooms and buildings that match what is typed.
    @ViewBuilder
    private func searchResults(now: Date) -> some View {
        let hits = MapSearch.hits(for: query, plans: scene.plans, catalogue: rooms.rooms)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Scrivi il codice di un'aula, come 3.1.2 o T.1.2, oppure il numero di un edificio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if hits.isEmpty {
            Text("Nessuna aula o edificio del campus 3D con “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 0) {
            ForEach(hits) { hit in
                Button {
                    endSearch()
                    Task { await scene.go(to: hit.level) }
                } label: {
                    let trailing: AnyView? = hit.csiv.map { AnyView(statusTag(status(of: classroom($0), now: now), now: now)) }
                    row(title: hit.title, detail: hit.detail, trailing: trailing,
                        symbol: hit.csiv == nil ? "building.2" : "door.left.hand.open")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Closes the search and puts the keyboard away.
    private func endSearch() {
        searchFocused = false
        searching = false
        query = ""
        expanded = false
    }

    // MARK: - Pieces

    /// One row of a list in the panel.
    private func row(title: String, detail: String?, trailing: AnyView?, symbol: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    /// "3 libere su 7" for some rooms, once any of their statuses is known, else how many
    /// rooms there are.
    private func countLabel(_ csivs: [String], now: Date) -> AnyView {
        let statuses = csivs.map { status(of: classroom($0), now: now) }
        let known = statuses.filter { $0 != .unknown }
        let free = statuses.filter(\.isFree).count
        let text = known.isEmpty
            ? String(localized: "\(csivs.count) aule")
            : String(localized: "\(free) libere su \(csivs.count)")
        return AnyView(Text(text).font(.subheadline).foregroundStyle(free > 0 ? Color.green : Color.secondary))
    }

    /// A room's status as a short tag: free with a tick, busy with a clock, nothing when unknown.
    @ViewBuilder
    private func statusTag(_ status: MapRoomStatus, now: Date) -> some View {
        switch status {
        case .unknown:
            EmptyView()
        case .free(let until):
            Label(until.map { String(localized: "fino alle \(clock($0))") } ?? String(localized: "libera"),
                  systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .busy(let until, _):
            Label(String(localized: "fino alle \(clock(until))"), systemImage: "clock")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    /// The room's status in a sentence, and whether the student's next lesson is in it.
    @ViewBuilder
    private func statusLine(_ room: Classroom?, now: Date) -> some View {
        let status = status(of: room, now: now)
        let text: String = switch status {
        case .unknown:
            aule.teachingDay.contains(now) || room == nil
                ? String(localized: "Occupazione non disponibile")
                : String(localized: "Fuori dall'orario delle lezioni")
        case .free(let until):
            until.map { String(localized: "Libera fino alle \(clock($0))") }
                ?? String(localized: "Libera per il resto della giornata")
        case .busy(let until, let what):
            what.map { String(localized: "Occupata fino alle \(clock(until)) · \($0)") }
                ?? String(localized: "Occupata fino alle \(clock(until))")
        }
        Label(text, systemImage: status.isFree ? "checkmark.circle.fill" : "clock")
            .font(.subheadline)
            .foregroundStyle(status.isFree ? Color.green : Color.secondary)
            .labelStyle(.titleAndIcon)
    }

    /// The status of a room at a moment, from the bookings held; unknown outside today's
    /// teaching day, when the free-rooms screen is looking at another day.
    private func status(of room: Classroom?, now: Date) -> MapRoomStatus {
        let day = aule.teachingDay
        guard day.contains(now) else { return .unknown }
        return MapRoomStatus.of(occupancy.bookings(of: room), at: now, dayEnd: day.end)
    }

    /// The catalogue's room for a space code of the model.
    private func classroom(_ csiv: String) -> Classroom? {
        rooms.rooms.first { $0.roomCode == csiv }
    }

    /// A room's door code from its space code, in the building on screen.
    private func sigla(_ csiv: String) -> String {
        scene.plan?.piani.flatMap(\.aule).first { $0.csiv == csiv }?.sigla ?? csiv
    }

    /// The floor the camera is on, if any.
    private var currentFloor: String? {
        switch scene.level {
        case .floor(let csip), .room(let csip, _), .inside(let csip, _): csip
        default: nil
        }
    }

    /// "5 piani · 38 aule" for a building, with how many are free once known.
    private func buildingSubtitle(_ csie: String, now: Date) -> String {
        let floors = scene.plans[csie]?.piani ?? []
        let csivs = floors.flatMap(\.aule).map(\.csiv)
        let free = csivs.filter { status(of: classroom($0), now: now).isFree }.count
        var parts = [String(localized: "\(floors.count) piani"), String(localized: "\(csivs.count) aule")]
        if free > 0 { parts.append(String(localized: "\(free) libere ora")) }
        return parts.joined(separator: " · ")
    }

    /// "Edificio 3 · 3 libere su 7" for a floor.
    private func floorSubtitle(_ csip: String, now: Date) -> String {
        let csivs = scene.plan?.piani.first { $0.csip == csip }?.aule.map(\.csiv) ?? []
        let free = csivs.filter { status(of: classroom($0), now: now).isFree }.count
        let building = MapNames.building(scene.plan, csie: scene.csie)
        return free > 0
            ? "\(building) · " + String(localized: "\(free) libere su \(csivs.count)")
            : "\(building) · " + String(localized: "\(csivs.count) aule")
    }

    /// A time of day as the app writes it.
    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// Walking directions to a building in Maps. Inside the building the map itself shows
    /// the floor and the room; the path between them needs the routes the models do not
    /// carry yet.
    private func directions(to csie: String) {
        Task {
            guard let point = await map.coordinate(of: csie),
                  let url = URL(string: "http://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)&dirflg=w")
            else { return }
            openURL(url)
        }
    }
}

// MARK: - Model

/// The bookings of the rooms in the buildings the map has visited, read once per room and day
/// through ``FreeRoomsModel/bookings(for:)``, whose cache the room pages share.
@Observable
final class MapOccupancy {
    /// Bookings by the room's door code; a room missing here is unknown, never free.
    private(set) var bookings: [String: [RoomBooking]] = [:]
    /// The rooms already asked about, answered or not.
    @ObservationIgnored private var asked: Set<String> = []
    /// How many rooms are asked about at once.
    static let concurrency = 6

    /// Reads the bookings of rooms not read yet, a few at a time.
    ///
    /// - Parameters:
    ///   - rooms: The rooms.
    ///   - aule: The model that fetches and caches bookings.
    func load(_ rooms: [Classroom], from aule: FreeRoomsModel) async {
        let wanted = rooms.filter { $0.occupancyID != nil && !asked.contains($0.id) }
        asked.formUnion(wanted.map(\.id))
        var start = 0
        while start < wanted.count {
            if Task.isCancelled { return }
            let chunk = Array(wanted[start..<min(start + Self.concurrency, wanted.count)])
            start += Self.concurrency
            await withTaskGroup(of: (String, [RoomBooking]?).self) { group in
                for room in chunk {
                    group.addTask { (room.id, await aule.bookings(for: room)) }
                }
                for await (id, value) in group {
                    if let value { bookings[id] = value }
                }
            }
        }
    }

    /// A room's bookings, when they have been read.
    func bookings(of room: Classroom?) -> [RoomBooking]? {
        room.flatMap { bookings[$0.id] }
    }
}

/// Proposes at most `maxHeight` to its content and takes the content's own size, so the
/// panel is as tall as what it holds and scrolls only past the cap. A `frame(maxHeight:)`
/// would instead grow every panel to the cap.
struct CappedHeight: Layout {
    /// The tallest the content may be.
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let height = min(proposal.height ?? maxHeight, maxHeight)
        return content.sizeThatFits(ProposedViewSize(width: proposal.width, height: height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Where on the 3D campus a catalogue room is.
enum MapTargets {
    /// The deepest level the model has for a room: the room itself, else its floor, else its
    /// building; `nil` when its building is not modelled.
    ///
    /// - Parameters:
    ///   - room: The catalogue's room.
    ///   - plans: The modelled buildings' plans, by `csie`.
    /// - Returns: The level.
    static func level(of room: Classroom, plans: [String: Trifoglio3DPlan]) -> Trifoglio3DLevel? {
        guard let plan = plans[room.buildingCode] else { return nil }
        if let csiv = room.roomCode,
           let floor = plan.piani.first(where: { floor in floor.aule.contains { $0.csiv == csiv } }) {
            return .room(floor: floor.csip, room: csiv)
        }
        if plan.piani.contains(where: { $0.csip == room.floorCode }) { return .floor(room.floorCode) }
        return .building(room.buildingCode)
    }
}

/// What the map's search finds: modelled rooms by their door code or catalogue name, and
/// buildings by number or name.
enum MapSearch {
    /// One result.
    struct Hit: Identifiable {
        /// The room's space code, or the building's code.
        let id: String
        /// What is shown in bold.
        let title: String
        /// Where it is.
        let detail: String?
        /// The room's space code, `nil` for a building.
        let csiv: String?
        /// Where the camera goes.
        let level: Trifoglio3DLevel
    }

    /// The results for some text, buildings first, at most twenty.
    ///
    /// - Parameters:
    ///   - query: What was typed.
    ///   - plans: The modelled buildings' plans, by `csie`.
    ///   - catalogue: The rooms catalogue, for the names the model does not carry.
    /// - Returns: The results.
    static func hits(for query: String, plans: [String: Trifoglio3DPlan], catalogue: [Classroom]) -> [Hit] {
        var text = query.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("aula ") { text = String(text.dropFirst(5)) }
        if text.hasPrefix("edificio ") { text = String(text.dropFirst(9)) }
        guard !text.isEmpty else { return [] }
        var buildings: [Hit] = []
        var rooms: [Hit] = []
        var seen: Set<String> = []
        for csie in Trifoglio3DScene.buildings {
            guard let plan = plans[csie] else { continue }
            let name = MapNames.building(plan, csie: csie)
            if plan.numero?.lowercased() == text || (plan.nome?.lowercased().contains(text) ?? false) {
                buildings.append(Hit(id: csie, title: name, detail: plan.nome, csiv: nil, level: .building(csie)))
            }
            for floor in plan.piani {
                for room in floor.aule where room.sigla.lowercased().contains(text) && !seen.contains(room.csiv) {
                    seen.insert(room.csiv)
                    rooms.append(Hit(id: room.csiv, title: room.sigla,
                                     detail: "\(name) · \(MapNames.floor(floor.csip))",
                                     csiv: room.csiv, level: .room(floor: floor.csip, room: room.csiv)))
                }
            }
        }
        for room in catalogue where room.id.lowercased().contains(text) {
            guard let csiv = room.roomCode, !seen.contains(csiv),
                  case .room(let csip, _)? = MapTargets.level(of: room, plans: plans) else { continue }
            seen.insert(csiv)
            rooms.append(Hit(id: csiv, title: room.id,
                             detail: "\(MapNames.building(plans[room.buildingCode], csie: room.buildingCode)) · \(MapNames.floor(csip))",
                             csiv: csiv, level: .room(floor: csip, room: csiv)))
        }
        rooms.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return Array((buildings + rooms).prefix(20))
    }
}

/// Names for the model's buildings and floors.
enum MapNames {
    /// "Edificio 3", from the plan's number, else the code.
    static func building(_ plan: Trifoglio3DPlan?, csie: String) -> String {
        String(localized: "Edificio \(plan?.numero ?? csie)")
    }

    /// A floor's name from the last characters of its code.
    static func floor(_ csip: String) -> String {
        switch csip.suffix(3) {
        case "00S": String(localized: "Seminterrato")
        case "000": String(localized: "Piano terra")
        case "S00": String(localized: "Soppalco")
        default: String(localized: "\(Int(csip.suffix(3)) ?? 0)° piano")
        }
    }

    /// A floor's name on a lift button: T, 1, 2, S for the basement, M for the mezzanine.
    static func floorShort(_ csip: String) -> String {
        switch csip.suffix(3) {
        case "00S": "S"
        case "000": "T"
        case "S00": "M"
        default: String(Int(csip.suffix(3)) ?? 0)
        }
    }
}

#Preview("Nuova mappa") {
    CampusMapScreen().previewInNavigation()
}
#endif

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
    /// Whether the panel, a system sheet, is up: while the map is on screen.
    @State private var sheetShown = false
    /// How tall the panel sheet stands.
    @State private var detent: PresentationDetent = MapDetents.compact
    /// The detent before the search took the whole height, to go back to.
    @State private var detentBeforeSearch = MapDetents.compact
    /// Whether the search page is pushed in the panel.
    @State private var searching = false
    /// Whether the search sheet's field has the keyboard.
    @State private var searchFieldActive = false
    /// What is typed in the search field.
    @State private var query = ""
    /// What the search shows: everything, rooms only or buildings only.
    @State private var scope = MapSearchScope.all
    /// Whether the panel shows the free rooms near a starting point, in place of the level.
    @State private var nearbyMode = false
    /// How long a room must stay free to be listed there, in minutes.
    @State private var nearbyMinutes = 60
    /// Where the nearby rooms are counted from.
    @State private var nearbyOrigin: MapNearby.Origin?
    /// Metres from the origin's building to each modelled building, when the coordinates are known.
    @State private var nearbyDistances: [String: Double] = [:]
    /// Whether bookings are still being read for the nearby rooms.
    @State private var nearbyLoading = false
    /// Whether a floor's list shows only the free rooms.
    @State private var onlyFree = false
    /// The room whose full page is pushed in the panel.
    @State private var details: Classroom?
    /// Whether Aule libere is pushed in the panel.
    @State private var showsFreeRooms = false
    /// Metres from the starting point's building to the buildings of the free rooms.
    @State private var freeMetres: [String: Double] = [:]
    /// Minutes on foot to the next lesson from the one before it, when both rooms are known.
    @State private var walk: (event: Int, minutes: Int, from: String)?
    /// The rooms and buildings opened from the search, most recent first, as text.
    @AppStorage("newMap.recents") private var recentsText = ""
    /// The low sheet's height on the campus, fitted to what it holds; 0 until measured.
    @State private var compactHeight: CGFloat = 0
    /// The lesson opened from its card, in the panel.
    @State private var lessonDetail: AgendaEvent?
    /// The service shown: its places in the panel, nearest first, and its pins on the campus.
    @State private var service: CampusService?
    /// Metres from the starting point to each of the service's places, by place.
    @State private var serviceMetres: [String: Double] = [:]
    /// The services' places and the buildings' access notes, kept across openings of the map.
    @State private var services = CampusServicesModel.shared
    /// Whether the building's access notes are shown in full.
    @State private var accessExpanded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.shell) private var shell
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
    /// The scene, what floats over it and the toolbar.
    private var screen: some View {
        Trifoglio3DStage(scene: scene, dark: dark)
            // In the stage's own frame, which the marks are projected into.
            .overlay(alignment: .topLeading) { servicePins }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { floorColumn.padding(.trailing, 16).padding(.top, 8) }
        // Only the map's own search makes room for the keyboard. Opened from Cerca with a room
        // just typed, the keyboard is still going down during the push, and the whole screen
        // was laid out above it, leaving a white band under the panel.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(dark ? Color(red: 0.05, green: 0.06, blue: 0.09) : Color(red: 0.91, green: 0.93, blue: 0.95))
        // The system bar stays, clear over the scene. On the campus its back button returns to
        // where the map was opened from, swipe included; deeper in, a button in the same place
        // goes up one level instead, so there is never more than one.
        // Named for the back stack and VoiceOver, but no title drawn over the scene, where it
        // would blend in with the roofs.
        .navigationTitle("Mappa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // The back button is the map's own, in the system's place and glass: with the panel
        // presented as a sheet, leaving must put the sheet away first, which the system back
        // button and its swipe would not wait for.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(verbatim: "") }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await goUp() }
                } label: {
                    // Text beside the chevron, as the system back button draws it: a
                    // Label in a toolbar would show the icon alone.
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").fontWeight(.semibold)
                        if !nearbyMode, service == nil, let parent = parentTitle { Text(parent) }
                    }
                }
                .accessibilityLabel(parentTitle.map { Text("Torna a \($0)") } ?? Text("Indietro"))
                .accessibilityIdentifier("newmap-back")
            }
            // The campus, as the title: choosing another moves the free count with it.
            if !nearbyMode, service == nil, scene.level == .campus, aule.campuses.count > 1 {
                // A glass of its own, apart from the back button's.
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) { campusMenu }
            }
            // A service keeps its name over the map, as the way out of it.
            if let service {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeService()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: service.symbol).imageScale(.small)
                            Text(service.title)
                        }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(Text("Esci da \(service.title)"))
                    .accessibilityIdentifier("newmap-service-close")
                }
            }
            // "Libere vicino a te" keeps its filters over the map, as in the design: the way
            // out, green, and how long the rooms must stay free.
            if nearbyMode {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        closeNearby()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Libere ora")
                        }
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.freeRoom)
                    .accessibilityLabel("Esci da Libere ora")
                    Menu {
                        Picker("Libere per", selection: $nearbyMinutes) {
                            Text("Per 30 min").tag(30)
                            Text("Per 1 ora").tag(60)
                            Text("Per 2 ore").tag(120)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(durationLabel)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        // The current class accessory hangs from the tab view, not the tab bar, so hiding the
        // bar leaves it floating over the panel.
        .onAppear {
            shell.coversTabBar = true
            sheetShown = true
        }
        .onDisappear {
            shell.coversTabBar = false
            sheetShown = false
        }
        // A container, so the identifier does not replace those of the buttons inside.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newmap")
    }

    /// The scene with its toolbar, the panel, and what is loaded for them. Split from ``screen``
    /// so the compiler checks each half in reasonable time.
    var body: some View {
        screen
        // The panel is a system sheet, as in Maps: its detents, drag and animations are the
        // system's, the scene stays usable under it up to the middle detent, and it cannot be
        // swiped away.
        .sheet(isPresented: $sheetShown) {
            panelSheet
                .presentationDetents([compactDetent, MapDetents.medium, MapDetents.room, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: MapDetents.medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onChange(of: scene.level) { _, level in
            withAnimation(.snappy) { detent = detentFor(level) }
        }
        .task { await rooms.load() }
        .task { await services.load() }
        // The pins follow the service's places, which grow as its floors are read.
        .onChange(of: markedBuildings) { _, buildings in
            scene.mark(buildings)
            Task { await measureService() }
        }
        // The free count follows the campus in the title; the 3D campus until one is chosen.
        .task(id: shownCampus ?? "") {
            if aule.campus == nil, let campus = mapCampus { aule.campus = campus }
            await aule.load()
            await measureFree()
        }
        .task(id: lessons?.next?.id ?? -1) { await measureWalk() }
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
                .sorted { (a: Classroom, b: Classroom) -> Bool in
                    (a.floorCode == floor ? 0 : 1) < (b.floorCode == floor ? 0 : 1)
                }
            Task { await occupancy.load(wanted, from: aule) }
        }
    }

    // MARK: - Over the scene

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

    /// One level up: from a room to its floor, from a floor to its building, from a building to
    /// the campus.
    private func goUp() async {
        if service != nil { closeService(); return }
        switch scene.level {
        case .campus:
            sheetShown = false
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
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
                // Says what the column is: the building's floors.
                Image(systemName: "square.3.layers.3d")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 30)
                    .accessibilityHidden(true)
                Divider().frame(width: 24)
                ForEach(plan.piani.reversed()) { floor in
                    let chosen = currentFloor == floor.csip
                    Button {
                        Task { await scene.go(to: .floor(floor.csip)) }
                    } label: {
                        Text(MapNames.floorShort(floor.csip))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(chosen ? Color.white : Color.primary)
                            .background { if chosen { Circle().fill(Color.accentColor) } }
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

    /// The panel's content in the sheet: a header that stays, the body, and the pages pushed
    /// from it (the search, a room's details, Aule libere).
    private var panelSheet: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let failure = scene.failure {
                            Text(failure).font(.footnote).foregroundStyle(.red)
                        }
                        header(now: context.date)
                        bodyContent(now: context.date)
                    }
                    .padding(.horizontal, 20)
                    // Titles sit lower under the grabber; the campus search field stays close.
                    .padding(.top, scene.level == .campus && !nearbyMode && service == nil ? 14 : 26)
                    .padding(.bottom, campusAtRest ? 20 : 24)
                    // On the campus at rest the low sheet is as tall as what it holds, so the
                    // chips are never cut, with or without a lesson.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard campusAtRest, detent == compactDetent else { return }
                        fitCompact(to: height)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $searching) { searchPage }
            .navigationDestination(item: $details) { room in ClassroomDetailView(room: room) }
            .navigationDestination(item: $lessonDetail) { event in EventDetailView(event: event) }
            .navigationDestination(isPresented: $showsFreeRooms) { FreeRoomsView() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newmap-panel")
    }

    /// The panel's header: the search field on the campus, else where the camera is.
    @ViewBuilder
    private func header(now: Date) -> some View {
        if nearbyMode {
            nearbyHeader
        } else if let service {
            serviceHeader(service)
        } else {
            switch scene.level {
            case .campus:
                Button {
                    searching = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Cerca aule ed edifici")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.secondary.opacity(0.14), in: innerShape)
                    .contentShape(innerShape)
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
                    Text("Leonardo › \(MapNames.building(scene.plan, csie: scene.csie)) › \(MapNames.floor(csip))")
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
            closeButton("Torna al campus") { Task { await scene.go(to: .campus) } }
        }
    }

    /// The panel's body for where the camera is.
    @ViewBuilder
    private func bodyContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: scene.level == .campus && !nearbyMode && service == nil ? 12 : 14) {
            if nearbyMode {
                nearbyBody(now: now)
            } else if let service {
                serviceBody(service, now: now)
            } else {
            switch scene.level {
            case .campus: campusBody(now: now)
            case .building(let csie): buildingBody(csie, now: now)
            case .floor(let csip): floorBody(csip, now: now)
            case .room(let csip, let csiv), .inside(let csip, let csiv): roomBody(floor: csip, room: csiv, now: now)
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Campus

    /// The lesson to go to, the free rooms near it, and a row of chips: the free rooms and
    /// the campus's services. Pulled up, the modelled buildings.
    @ViewBuilder
    private func campusBody(now: Date) -> some View {
        if let lessons {
            lessonCard(lessons, now: now)
        }
        freeRow
        // One row, scrolled sideways and running off the trailing edge: the free rooms, then
        // the services, which only the campus drawn in 3D can pin.
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    openFree()
                } label: {
                    chip("Libere ora", symbol: "checkmark", symbolColor: .freeRoom, on: false,
                         count: freeSummary.flatMap { $0.count > 0 ? $0.count : nil })
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aule libere ora")
                .accessibilityIdentifier("newmap-free-rooms")
                if campusHas3D {
                    ForEach(CampusService.allCases) { item in
                        Button {
                            openService(item)
                        } label: {
                            serviceChip(item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("newmap-service-\(item.rawValue)")
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.horizontal, -20)

        // The buildings wait under the fold: pulling the panel up shows them.
        if detent != compactDetent {
            sectionHeader("Edifici")
            listCard(modelledBuildings, id: \.self) { csie in
                Button {
                    Task { await scene.go(to: .building(csie)) }
                } label: {
                    row(title: MapNames.building(scene.plans[csie], csie: csie),
                        detail: MapNames.buildingDetail(scene.plans[csie], csie: csie), trailing: nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A filter or shortcut chip of the panel, with a count in a green badge when given.
    private func chip(_ title: LocalizedStringKey, symbol: String?, symbolColor: Color?, on: Bool,
                      count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .fontWeight(.bold)
                    .foregroundStyle(on ? AnyShapeStyle(onTint) : symbolColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            }
            Text(title).foregroundStyle(on ? onTint : .primary)
            if let count {
                Text(count, format: .number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.freeRoom, in: .capsule)
                    .contentTransition(.numericText())
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.14)), in: .capsule)
        .contentShape(.capsule)
    }

    /// A service's chip: its Maps-style badge and its name.
    private func serviceChip(_ item: CampusService) -> some View {
        HStack(spacing: 6) {
            ServiceBadge(service: item, size: 22)
            Text(item.title).foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Color.secondary.opacity(0.14), in: .capsule)
        .contentShape(.capsule)
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

    /// The lesson card: the one in progress and the one after it, or else the next one.
    @ViewBuilder
    private func lessonCard(_ lessons: MapLessonCard.Lessons, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let current = lessons.current {
                currentLesson(current, after: lessons.next, now: now)
            } else if let next = lessons.next {
                nextLesson(next, now: now)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(cardFill, in: innerShape)
        .containerShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newmap-next-lesson")
    }

    /// In progress: its room, its hours, how long is left on a bar; then the lesson after it,
    /// with the way there and the details.
    @ViewBuilder
    private func currentLesson(_ current: AgendaEvent, after: AgendaEvent?, now: Date) -> some View {
        let afterRoom = after.flatMap(lessonRoom)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(current.title).font(.headline).lineLimit(1)
                Text([String(localized: "In corso"), lessonRoom(current)?.id ?? current.roomLabel]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(clock(current.start))–\(clock(current.end))").font(.headline).monospacedDigit()
                Text(MapLessonCard.endsIn(from: now, to: current.end))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        Capsule()
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * MapLessonCard.progress(start: current.start, end: current.end, now: now))
                }
            }
            .accessibilityHidden(true)
        if let after {
            Divider()
            HStack(spacing: 10) {
                Text("Dopo")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                let title = Text(after.title).fontWeight(.semibold)
                Text("\(title) · \(afterRoom?.id ?? after.roomLabel ?? "") alle \(clock(after.start))")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let minutes = walkMinutes(to: after) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                        Text("\(minutes) min")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }
        }
        lessonButtons(
            primary: afterRoom.map { room in (String(localized: "Vai alla \(room.id)"), room.buildingCode) }
                ?? lessonRoom(current).map { (String(localized: "Indicazioni"), $0.buildingCode) },
            details: current)
    }

    /// Next today: its room, building and floor, when it starts, the walk from the lesson
    /// before, the way there and the details.
    @ViewBuilder
    private func nextLesson(_ next: AgendaEvent, now: Date) -> some View {
        let room = lessonRoom(next)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(next.title).font(.headline).lineLimit(1)
                Text(room.map { room in
                    String(localized: "Aula \(room.id) · \(buildingName(room.buildingCode)), \(MapNames.floor(room.floorCode))")
                } ?? next.roomLabel ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(clock(next.start)).font(.headline).monospacedDigit()
                Text(MapCounts.startsIn(from: now, to: next.start, ongoing: false))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if let walk, walk.event == next.id {
            HStack(spacing: 5) {
                Image(systemName: "figure.walk")
                Text("\(walk.minutes) min a piedi da \(walk.from)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, -4)
        }
        lessonButtons(primary: room.map { (String(localized: "Indicazioni"), $0.buildingCode) }, details: next)
    }

    /// The way there, filled, and the lesson's details, grey; the details alone when the room
    /// is not one the catalogue knows.
    private func lessonButtons(primary: (title: String, csie: String)?, details: AgendaEvent) -> some View {
        HStack(spacing: 8) {
            if let primary {
                Button {
                    directions(to: primary.csie)
                } label: {
                    Label(primary.title, systemImage: "figure.walk")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newmap-lesson-go")
            }
            Button {
                lessonDetail = details
            } label: {
                Text("Dettagli")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(onGrey)
                    .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newmap-show-next")
        }
        .font(.callout.weight(.semibold))
    }

    /// A lesson's room in the catalogue.
    private func lessonRoom(_ event: AgendaEvent) -> Classroom? {
        RelevanceOrder.room(named: [event.roomAcronym, event.room], in: rooms.rooms)
    }

    /// The minutes on foot to a lesson, once measured.
    private func walkMinutes(to event: AgendaEvent) -> Int? {
        walk.flatMap { $0.event == event.id ? $0.minutes : nil }
    }

    // MARK: Campus, free count, next lesson

    /// The campus the 3D model is of: the one most of the modelled buildings' rooms are on.
    private var mapCampus: String? {
        var counts: [String: Int] = [:]
        for room in rooms.rooms where Trifoglio3DScene.buildings.contains(room.buildingCode) {
            if let campus = room.campusName { counts[campus, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// The campus in the title, which the free count is of.
    private var shownCampus: String? { aule.campus ?? mapCampus }

    /// The campuses with a building drawn in 3D.
    private var modelledCampuses: Set<String> {
        Set(rooms.rooms.filter { Trifoglio3DScene.buildings.contains($0.buildingCode) }.compactMap(\.campusName))
    }

    /// Whether the campus in the title has buildings drawn in 3D.
    private var campusHas3D: Bool {
        guard let shownCampus, !modelledCampuses.isEmpty else { return true }
        return modelledCampuses.contains(shownCampus)
    }

    /// The campuses grouped by site, sites by name: the service counts free rooms per
    /// address, and a student knows the site the address is in.
    private var campusesBySite: [(site: String, campuses: [String])] {
        var siteOf: [String: String] = [:]
        for room in rooms.rooms {
            if let campus = room.campusName, let site = room.siteName { siteOf[campus] = site }
        }
        let groups = Dictionary(grouping: aule.campuses) { siteOf[$0] ?? String(localized: "Altre sedi") }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted()) }
    }

    /// The free rooms of the campus in the title and the nearest, once its bookings are in.
    private var freeSummary: MapFreeSummary.Summary? {
        guard !aule.rooms.isEmpty else { return nil }
        return MapFreeSummary.make(free: freeRooms, campus: shownCampus,
                                   origin: defaultOrigin()?.csie, metres: freeMetres)
    }

    /// The rooms free now, with where they are.
    private var freeRooms: [MapFreeSummary.Room] {
        let byID = Dictionary(rooms.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date.now
        return aule.freeNow().compactMap { schedule in
            byID[schedule.id].map {
                .init(id: $0.id, campus: $0.campusName, building: $0.buildingCode,
                      until: schedule.bookings.map(\.start).filter { $0 > now }.min())
            }
        }
    }

    /// The campus menu in the title.
    private var campusMenu: some View {
        Menu {
            Picker("Sede", selection: Binding(get: { shownCampus }, set: { aule.campus = $0 })) {
                ForEach(campusesBySite, id: \.site) { group in
                    Section(group.site) {
                        ForEach(group.campuses, id: \.self) { name in
                            if modelledCampuses.contains(name) {
                                Label(name, systemImage: "view.3d").tag(String?.some(name))
                            } else {
                                Text(name).tag(String?.some(name))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(shownCampus ?? String(localized: "Sede")).lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .fontWeight(.semibold)
            // As much room inside its glass as the filter capsule.
            .padding(.horizontal, 6)
        }
        // Black or white on the glass: the tint's light blue hardly reads on it at night.
        .tint(.primary)
        .accessibilityLabel(Text("Sede: \(shownCampus ?? "")"))
        .accessibilityIdentifier("newmap-campus")
    }

    /// "12 aule libere qui vicino · La più vicina: 3.0.1 · fino alle 16", opening the free
    /// rooms; on a campus without a 3D model, a line saying so instead of the nearest.
    @ViewBuilder
    private var freeRow: some View {
        if let summary = freeSummary {
            Button {
                openFree()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(MapCounts.freeNearbyTitle(summary.count))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let nearest = summary.nearest {
                            let code = Text(nearest).fontWeight(.semibold).foregroundStyle(.primary)
                            let until = Text(summary.until.map { String(localized: "fino alle \(clock($0))") }
                                             ?? String(localized: "tutto il giorno"))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.freeRoom)
                            Text("La più vicina: \(code) · \(until)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !campusHas3D, let campus = mapCampus {
                            Text("La mappa 3D per ora c'è solo per \(campus).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(cardFill, in: innerShape)
                .containerShape(.rect(cornerRadius: 26))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newmap-free-summary")
        }
    }

    /// ", stesso edificio" or ", Edificio 4" after the nearest room's code.
    private func nearestPlace(_ id: String) -> String {
        guard let room = rooms.rooms.first(where: { $0.id == id }) else { return "" }
        if room.buildingCode == defaultOrigin()?.csie { return String(localized: ", stesso edificio") }
        return room.buildingName.map { ", \($0)" } ?? ""
    }

    /// The free rooms: near you on the 3D campus, the list of Aule libere elsewhere.
    private func openFree() {
        if campusHas3D { openNearby() } else { showsFreeRooms = true }
    }

    /// Today's lessons, for the card.
    private var todayLessons: [AgendaEvent] {
        if let demo = MapLessonDemo.events(now: .now) { return demo }
        return agenda.events(on: .now)
    }

    /// The lesson in progress and the next one, for the card.
    private var lessons: MapLessonCard.Lessons? {
        MapLessonCard.pick(todayLessons, now: .now)
    }

    /// Reads how far the free rooms' buildings are from the starting point.
    private func measureFree() async {
        guard let origin = defaultOrigin()?.csie, let from = await map.coordinate(of: origin) else { return }
        var metres: [String: Double] = [:]
        for building in Set(freeRooms.map(\.building)) {
            guard let to = await map.coordinate(of: building) else { continue }
            metres[building] = MapNearby.metres(from: from, to: to)
        }
        freeMetres = metres
    }

    /// Reads the walk to the next lesson: from the lesson in progress, else from the one
    /// before it today. Nothing when either room is unknown or both are in one building.
    private func measureWalk() async {
        let events = todayLessons
        guard let next = lessons?.next,
              let before = MapLessonCard.walkStart(to: next, in: events, now: .now),
              let start = lessonRoom(before), let end = lessonRoom(next),
              start.buildingCode != end.buildingCode,
              let a = await map.coordinate(of: start.buildingCode),
              let b = await map.coordinate(of: end.buildingCode) else { walk = nil; return }
        walk = (next.id, MapWalk.minutes(metres: MapNearby.metres(from: a, to: b)), buildingName(start.buildingCode))
    }

    // MARK: Free near you

    /// Opens "Libere vicino a te" from the best starting point there is, and reads the rooms
    /// around it.
    private func openNearby() {
        nearbyOrigin = defaultOrigin()
        withAnimation(.snappy) {
            nearbyMode = true
            detent = MapDetents.medium
        }
        Task { await loadNearby() }
    }

    /// Leaves "Libere vicino a te" for the level on screen.
    private func closeNearby() {
        withAnimation(.snappy) {
            nearbyMode = false
            detent = detentFor(scene.level)
        }
    }

    /// The room of the lesson just ended or in progress, else the building or floor on
    /// screen, else the next lesson's building, else the first modelled building.
    private func defaultOrigin() -> MapNearby.Origin? {
        let now = Date.now
        let events = agenda.events(on: now)
        func place(of event: AgendaEvent) -> Classroom? {
            RelevanceOrder.room(named: [event.roomAcronym, event.room], in: rooms.rooms)
                .flatMap { scene.plans[$0.buildingCode] == nil ? nil : $0 }
        }
        if let event = events.last(where: { $0.start <= now && $0.end >= now.addingTimeInterval(-30 * 60) }),
           let room = place(of: event) {
            let reason = event.end <= now ? String(localized: "lezione appena finita") : String(localized: "lezione in corso")
            return .init(csie: room.buildingCode, csip: room.floorCode, reason: reason)
        }
        if scene.level != .campus, scene.plans[scene.csie] != nil {
            return .init(csie: scene.csie, csip: currentFloor, reason: String(localized: "sullo schermo"))
        }
        if let event = events.first(where: { $0.start > now }), let room = place(of: event) {
            return .init(csie: room.buildingCode, csip: nil, reason: String(localized: "prossima lezione"))
        }
        return modelledBuildings.first.map { .init(csie: $0, csip: nil, reason: nil) }
    }

    /// Reads the distances, then the bookings of the origin's building (its floor first) and
    /// of the three nearest, six rooms at a time.
    private func loadNearby() async {
        guard let origin = nearbyOrigin else { return }
        nearbyLoading = true
        defer { nearbyLoading = false }
        if let from = await map.coordinate(of: origin.csie) {
            var distances: [String: Double] = [:]
            for csie in modelledBuildings {
                guard let to = await map.coordinate(of: csie) else { continue }
                distances[csie] = MapNearby.metres(from: from, to: to)
            }
            nearbyDistances = distances
        } else {
            nearbyDistances = [:]
        }
        for csie in nearbyBuildings(from: origin) {
            let wanted = rooms.rooms
                .filter { $0.buildingCode == csie }
                .sorted { ($0.floorCode == origin.csip ? 0 : 1) < ($1.floorCode == origin.csip ? 0 : 1) }
            await occupancy.load(wanted, from: aule)
        }
    }

    /// The origin's building and the three nearest modelled ones.
    private func nearbyBuildings(from origin: MapNearby.Origin) -> [String] {
        let others = modelledBuildings.filter { $0 != origin.csie }
            .sorted { (nearbyDistances[$0] ?? .infinity) < (nearbyDistances[$1] ?? .infinity) }
        return [origin.csie] + others.prefix(3)
    }

    /// The title, the way out, the starting point and how long the rooms must stay free.
    private var nearbyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Libere vicino a te").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                closeButton("Esci da Libere ora") { closeNearby() }
            }
            originMenu { Task { await loadNearby() } }
        }
    }

    /// The starting point, as a menu of the modelled buildings.
    ///
    /// - Parameter picked: Called after a building is chosen.
    private func originMenu(_ picked: @escaping () -> Void) -> some View {
            Menu {
                ForEach(modelledBuildings, id: \.self) { csie in
                    Button(MapNames.building(scene.plans[csie], csie: csie)) {
                        nearbyOrigin = .init(csie: csie, csip: nil, reason: nil)
                        picked()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(originLabel).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.14), in: .capsule)
            }
            .tint(.primary)
            .padding(.bottom, 6)
    }

    /// "Da Edificio 3, 1° piano · lezione appena finita".
    private var originLabel: String {
        guard let origin = nearbyOrigin else { return String(localized: "Scegli un edificio") }
        var place = MapNames.building(scene.plans[origin.csie], csie: origin.csie)
        if let csip = origin.csip { place += ", " + MapNames.floor(csip) }
        let from = String(localized: "Da \(place)")
        return origin.reason.map { "\(from) · \($0)" } ?? from
    }

    private var durationLabel: String {
        switch nearbyMinutes {
        case 30: String(localized: "Per 30 min")
        case 120: String(localized: "Per 2 ore")
        default: String(localized: "Per 1 ora")
        }
    }

    /// The free rooms around the origin, nearest first, each taking the camera there.
    @ViewBuilder
    private func nearbyBody(now: Date) -> some View {
        let candidates = nearbyCandidates(now: now)
        if candidates.isEmpty, !nearbyLoading {
            Text("Nessuna aula libera qui vicino \(durationLabel.lowercased()).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(cardFill, in: innerShape)
        } else if !candidates.isEmpty {
            listCard(candidates, id: \.csiv) { item in
                Button {
                    closeNearby()
                    Task { await scene.go(to: .room(floor: item.csip, room: item.csiv)) }
                } label: {
                    HStack(spacing: 0) {
                        // "A - ALDO ROSSI" keeps only its code here; the full name is in the room's page.
                        Text(item.sigla.components(separatedBy: " - ").first ?? item.sigla)
                            .font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: 64, alignment: .leading).padding(.trailing, 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.relation).font(.headline).foregroundStyle(.primary)
                            if let seats = item.seats {
                                Text("\(seats) posti").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(item.until.map { String(localized: "fino alle \(clock($0))") } ?? String(localized: "tutto il giorno"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.freeRoom)
                    }
                    .frame(minHeight: 62)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        if nearbyLoading {
            Text("Controllo le altre aule…").font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The modelled rooms near the origin that stay free for the chosen time, nearest first.
    private func nearbyCandidates(now: Date) -> [MapNearby.Item] {
        guard let origin = nearbyOrigin else { return [] }
        let buildings = nearbyBuildings(from: origin)
        let wanted = now.addingTimeInterval(Double(nearbyMinutes) * 60)
        var items: [MapNearby.Item] = []
        for (rank, csie) in buildings.enumerated() {
            guard let plan = scene.plans[csie] else { continue }
            let originIndex = origin.csip.flatMap { csip in plan.piani.firstIndex { $0.csip == csip } }
            for (index, floor) in plan.piani.enumerated() {
                for room in floor.aule {
                    guard case .free(let until) = status(of: classroom(room.csiv), now: now),
                          until.map({ $0 >= wanted }) ?? true else { continue }
                    let relation: String
                    let steps: Int
                    if rank == 0 {
                        steps = originIndex.map { abs(index - $0) } ?? index
                        relation = originIndex.map { MapNearby.relation(floorsUp: index - $0) }
                            ?? MapNames.floor(floor.csip)
                    } else {
                        steps = 0
                        let name = MapNames.building(plan, csie: csie)
                        relation = nearbyDistances[csie].map { "\(name) · \(Int(($0 / 10).rounded()) * 10) m" } ?? name
                    }
                    items.append(.init(csiv: room.csiv, csip: floor.csip, sigla: room.sigla, seats: room.posti,
                                       relation: relation, until: until, rank: rank, steps: steps))
                }
            }
        }
        return items.sorted {
            ($0.rank, $0.steps, $0.sigla) < ($1.rank, $1.steps, $1.sigla)
        }
    }

    // MARK: Services

    /// Shows a service: its places nearest first from the best starting point, and its pins.
    private func openService(_ item: CampusService) {
        nearbyOrigin = defaultOrigin()
        serviceMetres = [:]
        withAnimation(.snappy) {
            service = item
            detent = MapDetents.medium
        }
        // Car parks have no building, so their pins never change: measure here too.
        Task { await measureService() }
        guard item.isPerFloor else { return }
        let floors = modelledBuildings.flatMap { scene.plans[$0]?.piani.map(\.csip) ?? [] }
        Task { await services.loadFloors(floors) }
    }

    /// Leaves the service for the level on screen.
    private func closeService() {
        withAnimation(.snappy) {
            service = nil
            detent = detentFor(scene.level)
        }
    }

    /// The service's places on the campus drawn in 3D.
    private var shownPlaces: [CampusPlace] {
        guard let service else { return [] }
        let area = Trifoglio3DScene.buildings.first.map { String($0.prefix(3)) }
        return services.places(service).filter { $0.area == area }
    }

    /// The service's places, nearest first.
    private var rankedPlaces: [CampusPlace] {
        CampusPlaces.nearest(shownPlaces, origin: nearbyOrigin?.csie, metres: serviceMetres)
    }

    /// The buildings to pin: those of the service's places.
    private var markedBuildings: Set<String> {
        Set(shownPlaces.compactMap(\.csie))
    }

    /// Reads how far each place is from the starting point: from where it stands when the
    /// service says, else from its building.
    private func measureService() async {
        guard service != nil, let origin = nearbyOrigin,
              let from = await map.coordinate(of: origin.csie) else { return }
        var metres: [String: Double] = [:]
        for place in shownPlaces {
            if let latitude = place.latitude, let longitude = place.longitude {
                metres[place.id] = MapNearby.metres(from: from, to: .init(latitude: latitude, longitude: longitude))
            } else if let csie = place.csie, let to = await map.coordinate(of: csie) {
                metres[place.id] = MapNearby.metres(from: from, to: to)
            }
        }
        serviceMetres = metres
    }

    /// The title and the starting point.
    private func serviceHeader(_ service: CampusService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.heading).font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                closeButton("Esci da \(service.title)") { closeService() }
            }
            originMenu { Task { await measureService() } }
        }
    }

    /// The places, nearest first, each taking the camera to its floor or building.
    @ViewBuilder
    private func serviceBody(_ service: CampusService, now: Date) -> some View {
        let places = Array(rankedPlaces.prefix(30))
        if places.isEmpty {
            Text(services.readingFloors ? "Controllo i piani degli edifici…" : "Nessun posto trovato su questo campus.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(cardFill, in: innerShape)
        } else {
            listCard(places, id: \.id) { place in
                Button {
                    openPlace(place)
                } label: {
                    placeRow(place, now: now)
                }
                .buttonStyle(.plain)
            }
            if services.readingFloors {
                Text("Controllo gli altri piani…").font(.footnote).foregroundStyle(.secondary)
            }
            if service == .parking {
                Text("I parcheggi sono per chi è autorizzato dal Politecnico, con il badge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One place: what it is, how far, and whether it is open or has room.
    private func placeRow(_ place: CampusPlace, now: Date) -> some View {
        HStack(spacing: 12) {
            ServiceBadge(service: place.service, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(placeTitle(place)).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(placeRelation(place)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            placeTrailing(place, now: now)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .contentShape(.rect)
    }

    /// The bar's or the car park's name; a fountain by where it is; a toilet by its building.
    private func placeTitle(_ place: CampusPlace) -> String {
        let building = place.csie.map(buildingName) ?? ""
        switch place.service {
        case .bar, .parking, .bikes: return place.name ?? place.detail ?? building
        case .water, .defibrillator: return place.detail ?? building
        case .toilets: return building
        case .study: return [place.name, building].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// "Stesso edificio · Un piano sopra", "1° piano · 120 m · 2 min".
    private func placeRelation(_ place: CampusPlace) -> String {
        var parts: [String] = []
        if let origin = nearbyOrigin, place.csie == origin.csie {
            parts.append(String(localized: "Stesso edificio"))
            if let csip = place.csip, let plan = scene.plans[origin.csie],
               let to = plan.piani.firstIndex(where: { $0.csip == csip }),
               let from = origin.csip.flatMap({ csip in plan.piani.firstIndex { $0.csip == csip } }) {
                parts.append(MapNearby.relation(floorsUp: to - from))
            } else if place.service.isPerFloor, let csip = place.csip {
                parts.append(MapNames.floor(csip))
            }
        } else {
            if place.service.isPerFloor, let csip = place.csip { parts.append(MapNames.floor(csip)) }
            if let metres = serviceMetres[place.id] {
                parts.append("\(Int((metres / 10).rounded()) * 10) m")
                parts.append(String(localized: "\(MapWalk.minutes(metres: metres)) min"))
            }
        }
        if parts.isEmpty, let detail = place.detail, detail != placeTitle(place) { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    /// Open until, free spaces, or accessible.
    @ViewBuilder
    private func placeTrailing(_ place: CampusPlace, now: Date) -> some View {
        switch place.service {
        case .parking where place.spaces != nil:
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(place.spaces ?? 0) liberi").font(.footnote.weight(.semibold)).foregroundStyle(Color.freeRoom)
                if let capacity = place.capacity {
                    Text("su \(capacity)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .parking, .bikes:
            if let count = place.spaces ?? place.capacity, count > 0 {
                Text("\(count) posti").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        case .bar:
            let parts = Calendar.current.dateComponents([.weekday, .hour, .minute], from: now)
            switch OpeningHours.state(place.hours, weekday: parts.weekday ?? 1,
                                      minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)) {
            case .open(let closes):
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Aperto").font(.footnote.weight(.semibold)).foregroundStyle(Color.freeRoom)
                    Text("fino alle \(OpeningHours.clock(closes))").font(.caption).foregroundStyle(.secondary)
                }
            case .opensLater(let at):
                Text("Apre alle \(OpeningHours.clock(at))").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            case .closed:
                Text("Chiuso").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        case .toilets where place.special:
            Image(systemName: "figure.roll")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityLabel("Accessibile")
        default:
            EmptyView()
        }
    }

    /// A building's name: its number in the 3D model, else the catalogue's.
    private func buildingName(_ csie: String) -> String {
        if let plan = scene.plans[csie] { return MapNames.building(plan, csie: csie) }
        return rooms.rooms.first { $0.buildingCode == csie }?.buildingName ?? MapNames.building(nil, csie: csie)
    }

    /// The camera to the place's floor or building; a place outside the model, in Maps.
    private func openPlace(_ place: CampusPlace) {
        guard let csie = place.csie, let plan = scene.plans[csie] else {
            if let latitude = place.latitude, let longitude = place.longitude,
               let url = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=w") {
                openURL(url)
            } else if let csie = place.csie {
                directions(to: csie)
            }
            return
        }
        closeService()
        Task {
            if let csip = place.csip, plan.piani.contains(where: { $0.csip == csip }) {
                await scene.go(to: .floor(csip))
            } else {
                await scene.go(to: .building(csie))
            }
        }
    }

    /// The service's pins over the campus, each with how many places its building has.
    @ViewBuilder
    private var servicePins: some View {
        if let service, scene.level == .campus {
            let counts = Dictionary(grouping: shownPlaces) { $0.csie ?? "" }.mapValues(\.count)
            ZStack(alignment: .topLeading) {
                ForEach(scene.markPoints.keys.sorted(), id: \.self) { csie in
                    if let point = scene.markPoints[csie] {
                        Button {
                            if let place = rankedPlaces.first(where: { $0.csie == csie }) { openPlace(place) }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: service.symbol)
                                if let count = counts[csie], count > 1 { Text(count, format: .number) }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(service.color, in: .capsule)
                            .overlay { Capsule().stroke(.white, lineWidth: 2) }
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(Text("\(service.title), \(buildingName(csie))"))
                        .position(x: point.x, y: point.y - 18)
                    }
                }
            }
        }
    }

    /// What the building's entrance is like, for wheelchair users first: three lines, the
    /// rest on a tap.
    private func accessCard(_ access: BuildingAccess) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accesso", systemImage: "figure.roll").font(.headline)
            if let text = access.accessible ?? access.general {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(accessExpanded ? nil : 2)
            }
            Button(accessExpanded ? "Meno" : "Altro") {
                withAnimation(.snappy) { accessExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(cardFill, in: innerShape)
        .containerShape(.rect(cornerRadius: 16))
        .accessibilityIdentifier("newmap-access")
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
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .foregroundStyle(.white)
        .controlSize(.large)

        if let access = services.access[csie] {
            accessCard(access)
        }

        listCard((scene.plans[csie]?.piani ?? []).reversed(), id: \.csip) { floor in
            Button {
                Task { await scene.go(to: .floor(floor.csip)) }
            } label: {
                floorRow(floor.csip, csivs: floor.aule.map(\.csiv), now: now)
            }
            .buttonStyle(.plain)
        }
    }

    /// A floor in the building's list: its name, how much of it is free as a bar, and the count.
    private func floorRow(_ csip: String, csivs: [String], now: Date) -> some View {
        let statuses = csivs.map { status(of: classroom($0), now: now) }
        let known = statuses.contains { $0 != .unknown }
        let free = statuses.filter(\.isFree).count
        return HStack(spacing: 12) {
            Text(MapNames.floor(csip))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 84, alignment: .leading)
            if known, !csivs.isEmpty {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 44, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.freeRoom)
                            .frame(width: 44 * CGFloat(free) / CGFloat(csivs.count), height: 6)
                    }
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            countLabel(csivs, now: now)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    // MARK: Floor

    /// The floor's rooms with their status, all or only the free ones.
    @ViewBuilder
    private func floorBody(_ csip: String, now: Date) -> some View {
        segmented

        let all = (scene.plan?.piani.first { $0.csip == csip }?.aule ?? [])
            .sorted { $0.sigla.localizedStandardCompare($1.sigla) == .orderedAscending }
        let shown = onlyFree ? all.filter { status(of: classroom($0.csiv), now: now).isFree } : all
        if shown.isEmpty {
            Text(onlyFree ? "Nessuna aula libera ora su questo piano." : "Nessuna aula su questo piano.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            listCard(shown, id: \.csiv) { room in
                Button {
                    Task { await scene.go(to: .room(floor: csip, room: room.csiv)) }
                } label: {
                    row(title: room.sigla, detail: room.posti.map { String(localized: "\($0) posti") },
                        trailing: AnyView(statusTag(status(of: classroom(room.csiv), now: now), now: now)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// All the floor's rooms or only the free ones: the system's segmented control.
    private var segmented: some View {
        Picker("Mostra", selection: $onlyFree) {
            Text("Tutte").tag(false)
            Text("Libere ora").tag(true)
        }
        .pickerStyle(.segmented)
        .controlSize(.extraLarge)
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
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .foregroundStyle(.white)
            if scene.interior(csiv) != nil {
                if case .inside = scene.level {
                    Button("Esci") { Task { await scene.go(to: .room(floor: csip, room: csiv)) } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(onGrey)
                } else {
                    Button("Entra") { Task { await scene.go(to: .inside(floor: csip, room: csiv)) } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(onGrey)
                }
            }
            if let room {
                Button("Dettagli") { details = room }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(onGrey)
            }
        }
        .controlSize(.large)

        if let bookings = occupancy.bookings(of: room) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Oggi").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                MapDayStrip(bookings: bookings, day: aule.teachingDay, mine: myLessons(in: room).map(\.interval), now: now)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(cardFill, in: innerShape)
            .containerShape(.rect(cornerRadius: 16))
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
        let recents = MapRecents.decode(recentsText)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            if recents.isEmpty {
                Text("Scrivi il codice di un'aula, come 3.1.2 o T.1.2, oppure il numero di un edificio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    sectionHeader("Recenti")
                    Spacer()
                    Button("Cancella") { recentsText = "" }
                        .font(.footnote.weight(.semibold))
                        .padding(.bottom, -8)
                }
                recentsCard(recents, now: now)
            }
        } else if hits.isEmpty {
            Text("Nessuna aula o edificio del campus 3D con “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
            ForEach(MapSearchScope.allCases, id: \.self) { option in
                Button {
                    scope = option
                } label: {
                    chip(option.title, symbol: nil, symbolColor: nil, on: scope == option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == option ? .isSelected : [])
            }
        }
        let roomHits = scope == .buildings ? [] : hits.filter { $0.csiv != nil }
        let buildingHits = scope == .rooms ? [] : hits.filter { $0.csiv == nil }
        if !roomHits.isEmpty {
            sectionHeader("Aule")
            hitsCard(roomHits, now: now)
        }
        if !buildingHits.isEmpty {
            sectionHeader("Edifici")
            hitsCard(buildingHits, now: now)
        }
    }

    /// Search results in a card, each one taking the camera there.
    private func hitsCard(_ hits: [MapSearch.Hit], now: Date) -> some View {
        listCard(hits, id: \.id) { hit in
            Button {
                remember(hit)
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

    /// The recent searches in a card, each taking the camera there again.
    private func recentsCard(_ recents: [MapRecent], now: Date) -> some View {
        listCard(recents, id: \.id) { recent in
            Button {
                recentsText = MapRecents.encode(MapRecents.adding(recent, to: recents))
                endSearch()
                Task {
                    switch recent.kind {
                    case .building: await scene.go(to: .building(recent.id))
                    case .room:
                        if let floor = recent.floor { await scene.go(to: .room(floor: floor, room: recent.id)) }
                    }
                }
            } label: {
                let trailing: AnyView? = recent.kind == .room
                    ? AnyView(statusTag(status(of: classroom(recent.id), now: now), now: now)) : nil
                row(title: recent.title, detail: recent.detail, trailing: trailing, symbol: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
        }
    }

    /// Keeps a search result among the recent ones.
    private func remember(_ hit: MapSearch.Hit) {
        let recent: MapRecent
        switch hit.level {
        case .room(let floor, let room):
            recent = MapRecent(kind: .room, id: room, floor: floor, title: hit.title, detail: hit.detail)
        case .building(let csie):
            recent = MapRecent(kind: .building, id: csie, floor: nil, title: hit.title, detail: hit.detail)
        default:
            return
        }
        recentsText = MapRecents.encode(MapRecents.adding(recent, to: MapRecents.decode(recentsText)))
    }

    /// Closes the search page.
    private func endSearch() {
        searchFieldActive = false
        searching = false
    }

    /// The search, pushed in the panel with the sheet at full height: the native field with
    /// its own clear button, the system close button, and the results.
    private var searchPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchResults(now: .now)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Cerca sulla mappa")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $query, isPresented: $searchFieldActive,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Aule ed edifici"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { endSearch() }
            }
        }
        .onAppear {
            detentBeforeSearch = detent == .large ? compactDetent : detent
            withAnimation(.snappy) { detent = .large }
            searchFieldActive = true
        }
        .onDisappear {
            query = ""
            scope = .all
            // A result has moved the camera: the sheet takes that level's height.
            withAnimation(.snappy) {
                // The low sheet may have been fitted again meanwhile: back to its current height.
                let before = [MapDetents.medium, MapDetents.room].contains(detentBeforeSearch) ? detentBeforeSearch : compactDetent
                detent = scene.level == .campus ? before : detentFor(scene.level)
            }
        }
    }

    // MARK: - Pieces

    /// The fill of the cards that group rows inside the glass panel: white by day, a light
    /// veil at night.
    private var cardFill: Color {
        dark ? Color(uiColor: .tertiarySystemBackground) : Color.white
    }

    /// What sits inside the panel, a card or a field: concentric with it, given its padding.
    private var innerShape: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(12)), isUniform: true)
    }

    /// The label on a grey button: the tint by day; white at night, where the light blue on
    /// grey glass hardly reads.
    private var onGrey: AnyShapeStyle {
        dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint)
    }

    /// The label on a filled tint button: white on the navy, dark on the light blue of night.
    private var onTint: Color {
        dark ? Color(white: 0.08) : .white
    }

    /// Whether the panel shows the campus with nothing chosen: the content the low sheet fits.
    private var campusAtRest: Bool {
        scene.level == .campus && !nearbyMode && service == nil
    }

    /// The low sheet: as tall as its content once measured, the fixed fraction before.
    private var compactDetent: PresentationDetent {
        compactHeight > 0 ? .height(compactHeight) : MapDetents.compact
    }

    /// The height for a level of the map, the low sheet fitted to its content.
    private func detentFor(_ level: Trifoglio3DLevel) -> PresentationDetent {
        let fixed = MapDetents.for(level)
        return fixed == MapDetents.compact ? compactDetent : fixed
    }

    /// Fits the low sheet to its content, up to 55% of the screen, keeping it selected.
    ///
    /// - Parameter content: The content's height.
    private func fitCompact(to content: CGFloat) {
        let screen = scene.viewSize.height > 0 ? scene.viewSize.height : 874
        let height = (min(content, screen * 0.55)).rounded()
        guard abs(height - compactHeight) >= 1 else { return }
        let wasCompact = detent == compactDetent
        compactHeight = height
        if wasCompact { detent = compactDetent }
    }

    /// The system's close button, in the system's glass circle, for leaving a level or a list.
    private func closeButton(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(role: .close, action: action)
            // Outside a toolbar the system writes "Chiudi": its xmark alone, as in a toolbar.
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier("newmap-close")
    }

    /// A small heading over a card.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.bottom, -8)
            .accessibilityAddTraits(.isHeader)
    }

    /// Rows grouped in a card, with hairlines between them.
    private func listCard<Item, ID: Hashable, Row: View>(
        _ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(item)
                if index < items.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 18)
        .background(cardFill, in: innerShape)
            .containerShape(.rect(cornerRadius: 16))
    }

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
            ? MapCounts.rooms(csivs.count)
            : MapCounts.free(free, of: csivs.count)
        return AnyView(Text(text).font(.subheadline).lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(free > 0 ? Color.freeRoom : Color.secondary))
    }

    /// A room's status as a short tag in its colour: green while free, red while busy, nothing when unknown.
    @ViewBuilder
    private func statusTag(_ status: MapRoomStatus, now: Date) -> some View {
        switch status {
        case .unknown:
            EmptyView()
        // The colour says it: green while free, red while busy, without icons.
        case .free(let until):
            Text(until.map { String(localized: "fino alle \(clock($0))") } ?? String(localized: "libera"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.freeRoom)
                .accessibilityLabel(until.map { Text("Libera fino alle \(clock($0))") } ?? Text("Libera"))
        case .busy(let until, _):
            Text(String(localized: "occupata fino alle \(clock(until))"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityLabel(Text("Occupata fino alle \(clock(until))"))
        }
    }

    /// The room's status in a sentence, and whether the student's next lesson is in it.
    @ViewBuilder
    private func statusLine(_ room: Classroom?, now: Date) -> some View {
        let day = aule.teachingDay
        let bookings = occupancy.bookings(of: room)
        let (text, tone): (String, MapRoomTone) = if room == nil {
            (String(localized: "Stato non disponibile"), .unknown)
        } else if bookings == nil, day.contains(now) {
            (String(localized: "Controllo le prenotazioni…"), .unknown)
        } else if !day.contains(now), now < day.start {
            (String(localized: "Fuori dall'orario delle lezioni"), .unknown)
        } else {
            MapRoomSentence.make(bookings: bookings ?? [], own: myLessons(in: room).map {
                MapOwnLesson(title: $0.title, interval: $0.interval)
            }, now: now, dayEnd: day.end)
        }
        // Plain text, with only the parts that matter in bold; grey while nothing is known.
        Text(MapRoomSentence.styled(text))
            .font(.subheadline)
            .foregroundStyle(tone == .unknown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The status of a room at a moment, from the bookings held; unknown outside today's
    /// teaching day, when the free-rooms screen is looking at another day.
    private func status(of room: Classroom?, now: Date) -> MapRoomStatus {
        let day = aule.teachingDay
        guard day.contains(now) else { return .unknown }
        return MapRoomStatus.of(occupancy.bookings(of: room), at: now, dayEnd: day.end)
    }

    /// The student's own lessons today in a room: the day strip draws them in the tint and
    /// the room's sentence names them.
    private func myLessons(in room: Classroom?) -> [(title: String, interval: DateInterval)] {
        guard let room else { return [] }
        return agenda.events(on: .now).compactMap { event in
            let held = RelevanceOrder.room(named: [event.roomAcronym, event.room], in: rooms.rooms)
            guard held?.id == room.id else { return nil }
            return (event.title, DateInterval(start: event.start, end: max(event.start, event.end)))
        }
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
        let statuses = csivs.map { status(of: classroom($0), now: now) }
        let free = statuses.filter(\.isFree).count
        var parts = ["Leonardo", MapCounts.floors(floors.count), MapCounts.rooms(csivs.count)]
        if statuses.contains(where: { $0 != .unknown }) { parts.append(MapCounts.freeNow(free)) }
        return parts.joined(separator: " · ")
    }

    /// "Edificio 3 · 3 libere su 7" for a floor.
    private func floorSubtitle(_ csip: String, now: Date) -> String {
        let csivs = scene.plan?.piani.first { $0.csip == csip }?.aule.map(\.csiv) ?? []
        let statuses = csivs.map { status(of: classroom($0), now: now) }
        let free = statuses.filter(\.isFree).count
        let building = MapNames.building(scene.plan, csie: scene.csie)
        return statuses.contains(where: { $0 != .unknown })
            ? "\(building) · " + MapCounts.free(free, of: csivs.count)
            : "\(building) · " + MapCounts.rooms(csivs.count)
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
                buildings.append(Hit(id: csie, title: name, detail: MapNames.buildingDetail(plan, csie: csie),
                                     csiv: nil, level: .building(csie)))
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
    /// "Edificio 3", from the plan's number; a building with no number goes by its name, such
    /// as "Casa dello Studente", and by its code only when it has neither.
    static func building(_ plan: Trifoglio3DPlan?, csie: String) -> String {
        if let numero = plan?.numero?.trimmingCharacters(in: .whitespaces), !numero.isEmpty {
            return String(localized: "Edificio \(numero)")
        }
        if let nome = plan?.nome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty { return nome }
        return String(localized: "Edificio \(csie)")
    }

    /// The building's name under its title, unless the title already is the name.
    static func buildingDetail(_ plan: Trifoglio3DPlan?, csie: String) -> String? {
        guard let nome = plan?.nome, !nome.isEmpty, nome != building(plan, csie: csie) else { return nil }
        return nome
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

/// Lessons to photograph the card with, from the launch arguments: `-MapLessonDemo inCorso`
/// for one in progress and one after it, `-MapLessonDemo prossima` for one still to come.
enum MapLessonDemo {
    static func events(now: Date) -> [AgendaEvent]? {
        guard let index = CommandLine.arguments.firstIndex(of: "-MapLessonDemo"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        func lesson(_ id: Int, _ title: String, _ from: Double, _ to: Double, _ room: String) -> AgendaEvent {
            AgendaEvent(id: id, title: title, start: now.addingTimeInterval(from * 60),
                        end: now.addingTimeInterval(to * 60), kind: .lecture, room: room,
                        roomAcronym: room, calendarName: nil)
        }
        switch CommandLine.arguments[index + 1] {
        case "inCorso":
            return [lesson(-11, "Reti di Calcolatori", -80, 40, "B.5.1"), lesson(-12, "Analisi II", 55, 160, "3.1.2")]
        default:
            return [lesson(-21, "Fisica", -120, -20, "B.5.1"), lesson(-22, "Analisi II", 25, 145, "3.1.2")]
        }
    }
}

/// A service's mark, as Maps draws its categories: a white glyph in a circle of the category's
/// colour. In the chips, the list rows, and on the campus.
struct ServiceBadge: View {
    let service: CampusService
    let size: CGFloat

    var body: some View {
        Image(systemName: service.symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(service.color.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

extension CampusService {
    /// The category's colour, as Maps gives it: orange for food and drink, blue for parking,
    /// red for health. System colours, which adapt to the dark.
    var color: Color {
        switch self {
        case .bar: .orange
        case .water: .cyan
        case .toilets: .indigo
        case .bikes: .mint
        case .parking: .blue
        case .defibrillator: .red
        case .study: .brown
        }
    }
}
#endif


/// What the map's search shows.
enum MapSearchScope: CaseIterable {
    case all, rooms, buildings

    /// The chip's name.
    var title: LocalizedStringKey {
        switch self {
        case .all: "Tutto"
        case .rooms: "Aule"
        case .buildings: "Edifici"
        }
    }
}

/// A room's teaching day at a glance: a light green track for the free time, each booking a
/// red block (the student's own lesson in the tint), a thin line with a dot for now, and the
/// hours every three underneath. Red means busy here, so "now" is drawn in the primary colour.
private struct MapDayStrip: View {
    /// The room's bookings for the day.
    let bookings: [RoomBooking]
    /// The span the track covers.
    let day: DateInterval
    /// The student's own lessons in the room.
    let mine: [DateInterval]
    /// The moment the marker shows.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    ConcentricRectangle(corners: .concentric(minimum: .fixed(6)), isUniform: true)
                        .fill(Color.freeRoom.opacity(0.22))
                        .frame(height: 30)
                        .offset(y: 6)
                    ForEach(bookings) { booking in
                        let frame = slot(booking.interval, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isMine(booking) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.red.opacity(0.8)))
                                .frame(width: max(frame.width - 2, 3), height: 30)
                                .offset(x: frame.start + 1, y: 6)
                        }
                    }
                    if day.contains(now) {
                        let x = position(now, width: width)
                        Rectangle().fill(.primary).frame(width: 2, height: 38).offset(x: x - 1, y: 2)
                        Circle().fill(.primary).frame(width: 8, height: 8).offset(x: x - 4, y: -2)
                    }
                }
            }
            .frame(height: 40)

            GeometryReader { geometry in
                ForEach(hours, id: \.self) { hour in
                    Text(hour.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: position(hour, width: geometry.size.width), y: 6)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    /// The hours labelled under the track: every three from the start of the day.
    private var hours: [Date] {
        var result: [Date] = []
        var hour = Calendar.current.dateInterval(of: .hour, for: day.start)?.start ?? day.start
        if hour < day.start { hour = hour.addingTimeInterval(3600) }
        while hour <= day.end {
            result.append(hour)
            hour = hour.addingTimeInterval(3 * 3600)
        }
        return result
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        guard day.duration > 0 else { return 0 }
        let fraction = min(max(date.timeIntervalSince(day.start) / day.duration, 0), 1)
        return width * fraction
    }

    private func slot(_ interval: DateInterval, width: CGFloat) -> (start: CGFloat, width: CGFloat) {
        let start = position(max(interval.start, day.start), width: width)
        let end = position(min(interval.end, day.end), width: width)
        return (start, max(end - start, 0))
    }

    private func isMine(_ booking: RoomBooking) -> Bool {
        mine.contains { $0.intersects(booking.interval) && $0.intersection(with: booking.interval)?.duration ?? 0 > 0 }
    }

    private var accessibilityText: Text {
        guard !bookings.isEmpty else { return Text("Libera tutto il giorno") }
        let ranges = bookings
            .sorted { $0.start < $1.start }
            .map { "\($0.start.formatted(date: .omitted, time: .shortened))–\($0.end.formatted(date: .omitted, time: .shortened))" }
            .joined(separator: ", ")
        return Text("Occupata \(ranges)")
    }
}

/// The heights the panel sheet stands at: compact on the campus, half-way inside a building,
/// and the whole screen for the search.
enum MapDetents {
    static let compact = PresentationDetent.fraction(0.45)
    static let medium = PresentationDetent.fraction(0.6)
    /// A room's panel, as in the design: the lit room stays in view above it.
    static let room = PresentationDetent.fraction(0.5)

    /// The height for a level of the map.
    static func `for`(_ level: Trifoglio3DLevel) -> PresentationDetent {
        switch level {
        case .campus: compact
        case .building, .floor: medium
        case .room, .inside: room
        }
    }
}

/// "Libere vicino a te": where the rooms are counted from, and how near each one is.
enum MapNearby {
    /// The starting point: a building, a floor when known, and why it was picked.
    struct Origin: Equatable {
        let csie: String
        let csip: String?
        let reason: String?
    }

    /// One free room in the list.
    struct Item {
        let csiv: String
        let csip: String
        let sigla: String
        let seats: Int?
        let relation: String
        let until: Date?
        /// 0 for the origin's building, then by distance.
        let rank: Int
        /// Floors away from the origin, in its building.
        let steps: Int
    }

    /// "Stesso piano", "Un piano sopra", "Due piani sotto".
    static func relation(floorsUp: Int) -> String {
        switch floorsUp {
        case 0: String(localized: "Stesso piano")
        case 1: String(localized: "Un piano sopra")
        case -1: String(localized: "Un piano sotto")
        case 2: String(localized: "Due piani sopra")
        case -2: String(localized: "Due piani sotto")
        case 3: String(localized: "Tre piani sopra")
        case -3: String(localized: "Tre piani sotto")
        case 4: String(localized: "Quattro piani sopra")
        case -4: String(localized: "Quattro piani sotto")
        case 5: String(localized: "Cinque piani sopra")
        case -5: String(localized: "Cinque piani sotto")
        case let n where n > 0: String(localized: "\(n) piani sopra")
        default: String(localized: "\(-floorsUp) piani sotto")
        }
    }

    /// The straight-line distance between two points, in metres.
    static func metres(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}


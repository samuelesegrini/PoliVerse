import SwiftUI

/// Which rooms are free, and for how long.
struct FreeRoomsView: View {
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var aule
    /// Whether the app is on screen, in the foreground or in the background.
    @Environment(\.scenePhase) private var scenePhase

    /// The shortest gap worth listing.
    /// Whether to list only the rooms free now, rather than every room with a gap today.
    @State private var minimumMinutes = 30
    @State private var onlyNow = true
    /// The rooms listed, in the order they are on screen, and which list they are
    /// of. Rooms arriving go below these while the pass runs.
    @State private var shown: (list: String, ids: [String]) = ("", [])
    /// Whether the list is being scrolled: it is not reordered under a finger.
    @State private var scrolling = false

    /// The view's content.
    var body: some View {
        @Bindable var aule = aule
        let rows = self.rows
        let ids = rows.map(\.room.id)

        List {
            Section {
                PageHero(symbol: "door.left.hand.open", title: Text("Aule libere"), summary: Text("Adesso e più tardi, per sede"))
                    .listHeader()
            }
            Section {
                DatePicker("Giorno", selection: $aule.day, displayedComponents: .date)
                if aule.campuses.count > 1 {
                    Picker("Sede", selection: $aule.campus) {
                        ForEach(aule.campuses, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                }
                Toggle("Solo libere adesso", isOn: $onlyNow)
                    .disabled(!isToday)
                Picker("Almeno", selection: $minimumMinutes) {
                    Text("30 min").tag(30)
                    Text("1 ora").tag(60)
                    Text("2 ore").tag(120)
                }
                .pickerStyle(.segmented)
            }
            .lookRow()

            content(rows)
        }
        .lookList()
        .animation(.default, value: ids)
        .onChange(of: ids, initial: true) { _, ids in shown = (list, ids) }
        .onScrollPhaseChange { _, phase in scrolling = phase.isScrolling }
        // A booking started or ended: the list is drawn again from the bookings
        // held, and the rooms that changed are asked about once.
        .onChange(of: aule.boundaryTick) { _, _ in
            guard scenePhase == .active else { return }
            Task { await aule.refreshAfterBoundary() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBar(age: aule.age) }
        .navigationTitle("Aule libere")
        .navigationBarTitleDisplayMode(.inline)
        .task { await aule.load() }
        // Re-fetches when the day or campus changes; the service keys its
        // cache on both, so flipping back to a day already seen costs nothing.
        .task(id: "\(aule.day.timeIntervalSince1970)|\(aule.campus ?? "")") {
            await aule.load()
        }
        .screenLedger("Aule libere", hasContent: !aule.rooms.isEmpty,
                      isComplete: !aule.isLoading && !aule.rooms.isEmpty)
        .refreshable { await aule.load(force: true) }
        // Free rooms is not in ``FreshnessCoordinator``: a campus pass is up
        // to 158 requests, which is not something to spend every time the app
        // comes forward. It is spent here, where the screen asking the
        // question is the one on display, and the service's 60-second window
        // makes a quick glance away and back free.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await aule.load() }
        }
        .onChange(of: aule.day) { _, _ in
            // "Free now" means nothing on a day that is not today.
            if !isToday { onlyNow = false }
        }
    }

    /// Whether the day being shown is today, since “free now” is only a question about today.
    private var isToday: Bool {
        PoliMiDate.romeCalendar.isDateInToday(aule.day)
    }

    /// Whether the list on screen is the rooms free now.
    private var showsNow: Bool { onlyNow && isToday }

    /// Names the list on screen, so an order kept for one is not applied to another.
    private var list: String {
        "\(showsNow)|\(minimumMinutes)|\(aule.day.timeIntervalSince1970)|\(aule.campus ?? "")"
    }

    /// The rooms to list, in the order to list them.
    ///
    /// While rooms are arriving or the list is being scrolled, the rows on screen
    /// keep their places and new rooms go below (``StableOrder``); once the pass
    /// is over and the list is still, it takes its sorted order.
    private var rows: [(room: RoomSchedule, slots: [DateInterval])] {
        let sorted: [(room: RoomSchedule, slots: [DateInterval])] = showsNow
            ? aule.freeNow().map { ($0, []) }
            : aule.freeRooms(minimumMinutes: minimumMinutes)
        let order = StableOrder.merge(
            shown: shown.list == list ? shown.ids : [],
            sorted: sorted.map(\.room.id),
            settle: !aule.isLoading && !scrolling)
        let byID = Dictionary(sorted.map { ($0.room.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    /// How far the pass is, while rooms are already listed.
    @ViewBuilder
    private var arriving: some View {
        if aule.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("\(aule.progress.done) di \(aule.progress.total) aule")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The rooms, or what is happening instead: a pass in flight, a failure, or a campus with
    /// nothing to show.
    ///
    /// - Parameter rows: The rooms to list, in order.
    @ViewBuilder
    private func content(_ rows: [(room: RoomSchedule, slots: [DateInterval])]) -> some View {
        if let message = aule.errorMessage {
            ContentUnavailableView("Aule non disponibili",
                                   systemImage: "building.2",
                                   description: Text(message))
        } else if aule.isLoading && aule.rooms.isEmpty {
            Section {
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(aule.progress.done),
                        total: Double(max(aule.progress.total, 1)))
                    Text("\(aule.progress.done) di \(aule.progress.total) aule")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lookRow()
        } else if showsNow {
            freeNowSection(rows.map(\.room))
        } else {
            daySection(rows)
        }
    }

    /// The rooms free for the next half hour, by name.
    private func freeNowSection(_ free: [RoomSchedule]) -> some View {
        Section {
            arriving
            if free.isEmpty, aule.isLoading {
                // Not yet "none": the rooms asked so far are busy, the rest are coming.
            } else if free.isEmpty {
                Text("Nessuna aula libera in questo momento.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(free) { room in
                    NavigationLink {
                        RoomScheduleView(room: room, day: aule.teachingDay)
                    } label: {
                        RoomFreeRow(room: room, slots: [])
                    }
                }
            }
        } header: {
            Text("Libere ora — \(free.count)")
        } footer: {
            Text("Libere per almeno la prossima mezz'ora.")
        }
        .lookRow()
    }

    /// Every room with a gap today, most free time first, each with its gaps.
    private func daySection(_ results: [(room: RoomSchedule, slots: [DateInterval])]) -> some View {
        Section {
            arriving
            if results.isEmpty, aule.isLoading {
                // Not yet "none": the rest of the campus is still coming.
            } else if results.isEmpty {
                Text("Nessuna aula con un intervallo libero abbastanza lungo.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results, id: \.room.id) { entry in
                    NavigationLink {
                        RoomScheduleView(room: entry.room, day: aule.teachingDay)
                    } label: {
                        RoomFreeRow(room: entry.room, slots: entry.slots)
                    }
                }
            }
        } header: {
            Text("\(results.count) aule")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fasce libere tra le 8:00 e le 20:00, ricavate dalle lezioni prenotate. Un'aula libera può comunque essere chiusa.")
                if !aule.hiddenRooms.isEmpty {
                    // Named rather than quietly omitted: these rooms are not
                    // free, they are unknown, and a student should be told
                    // which ones this screen cannot speak for.
                    Text("Il Politecnico non pubblica le occupazioni di \(aule.hiddenRooms.count) aule, che non compaiono qui.")
                }
            }
        }
        .lookRow()
    }
}

/// One room and the times it is free.
private struct RoomFreeRow: View {
    /// The room this row shows.
    let room: RoomSchedule
    /// When it is free.
    let slots: [DateInterval]

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(room.name).font(.subheadline.weight(.semibold))
                Spacer()
                if let seats = room.seats, seats > 0 {
                    Label("\(seats)", systemImage: "person.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let building = room.building {
                Text(building).font(.caption).foregroundStyle(.secondary)
            }
            if !slots.isEmpty {
                Text(slots.map(RoomScheduleView.format).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One room's day: what is booked and what is not.
struct RoomScheduleView: View {
    /// The room whose day is shown.
    let room: RoomSchedule
    /// The teaching day the timeline covers.
    let day: DateInterval

    /// The view's content.
    var body: some View {
        List {
            Section {
                PageHero(symbol: "clock", title: Text(verbatim: room.name), summary: Text("Quando è libera e quando no"))
                    .listHeader()
            }
            Section("Libera") {
                let free = room.freeSlots(in: day)
                if free.isEmpty {
                    Text("Occupata tutto il giorno.").foregroundStyle(.secondary)
                } else {
                    ForEach(free, id: \.start) { slot in
                        Label(Self.format(slot), systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.brand)
                    }
                }
            }
            .lookRow()

            RoomFacilitiesSection(roomID: room.occupancyID)

            Section("Occupata") {
                if room.bookings.isEmpty {
                    Text("Nessuna prenotazione.").foregroundStyle(.secondary)
                } else {
                    ForEach(room.bookings) { booking in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.format(booking.interval))
                                .font(.subheadline.weight(.medium))
                            if let title = booking.title {
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .lookRow()
        }
        .lookList()
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A span as `HH:mm–HH:mm` in Rome.
    ///
    /// - Parameter interval: The span to format.
    /// - Returns: The text.
    static func format(_ interval: DateInterval) -> String {
        let clock = RoomBooking.clock
        return "\(clock.string(from: interval.start))–\(clock.string(from: interval.end))"
    }
}

// MARK: - Previews

#Preview("Aule libere") {
    FreeRoomsView().previewInNavigation()
}

#Preview("Giornata di un'aula") {
    RoomScheduleView(
        room: RoomSchedule.samples(on: .now)[0],
        day: DateInterval(start: PoliMiDate.time(8, on: .now),
                          end: PoliMiDate.time(20, on: .now)))
    .previewInNavigation()
}

#Preview("Componente · Aula libera") {
    let day = DateInterval(start: PoliMiDate.time(8, on: .now),
                           end: PoliMiDate.time(20, on: .now))
    return List {
        ForEach(RoomSchedule.samples(on: .now)) { room in
            RoomFreeRow(room: room, slots: room.freeSlots(in: day))
        }
    }
    .previewEnvironment()
}

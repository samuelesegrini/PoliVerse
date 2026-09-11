import SwiftUI

/// Which rooms are free, and for how long.
struct FreeRoomsView: View {
    @Environment(FreeRoomsService.self) private var aule

    @State private var minimumMinutes = 30
    @State private var onlyNow = true

    var body: some View {
        @Bindable var aule = aule

        List {
            Section {
                DatePicker("Giorno", selection: $aule.day, displayedComponents: .date)
                if aule.sites.count > 1 {
                    Picker("Sede", selection: $aule.siteID) {
                        ForEach(aule.sites) { site in
                            Text(site.name).tag(String?.some(site.id))
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

            content
        }
        .navigationTitle("Aule libere")
        .navigationBarTitleDisplayMode(.inline)
        .task { await aule.load() }
        // Re-fetches when the day or campus changes; the service keys its
        // cache on both, so flipping back to a day already seen costs nothing.
        .task(id: "\(aule.day.timeIntervalSince1970)|\(aule.siteID ?? "")") {
            await aule.load()
        }
        .refreshable { await aule.load(force: true) }
        .onChange(of: aule.day) { _, _ in
            // "Free now" means nothing on a day that is not today.
            if !isToday { onlyNow = false }
        }
    }

    private var isToday: Bool {
        PoliMiDate.romeCalendar.isDateInToday(aule.day)
    }

    @ViewBuilder
    private var content: some View {
        if aule.notEntitled {
            // Said plainly rather than as a generic failure: this is a fact
            // about the account, not a fault, and no amount of retrying or
            // signing in again will change it.
            ContentUnavailableView(
                "Non disponibile per il tuo profilo",
                systemImage: "lock",
                description: Text("Il Politecnico riserva il servizio prenotazioni aule ad altri profili. L'elenco completo delle aule resta consultabile."))
        } else if let message = aule.errorMessage {
            ContentUnavailableView("Aule non disponibili",
                                   systemImage: "building.2",
                                   description: Text(message))
        } else if aule.payloadUnreadable {
            ContentUnavailableView(
                "Formato non riconosciuto",
                systemImage: "questionmark.circle",
                description: Text("Il Politecnico ha risposto in un formato che PoliVerse non sa ancora leggere."))
        } else if aule.isLoading && aule.rooms.isEmpty {
            Section { ProgressView().frame(maxWidth: .infinity) }
        } else if onlyNow && isToday {
            freeNowSection
        } else {
            daySection
        }
    }

    private var freeNowSection: some View {
        let free = aule.freeNow()
        return Section {
            if free.isEmpty {
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
    }

    private var daySection: some View {
        let results = aule.freeRooms(minimumMinutes: minimumMinutes)
        return Section {
            if results.isEmpty {
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
            Text("Fasce libere tra le 8:00 e le 20:00, ricavate dalle lezioni prenotate. Un'aula libera può comunque essere chiusa.")
        }
    }
}

private struct RoomFreeRow: View {
    let room: RoomSchedule
    let slots: [DateInterval]

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
    let room: RoomSchedule
    let day: DateInterval

    var body: some View {
        List {
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
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    static func format(_ interval: DateInterval) -> String {
        let clock = RoomBooking.clock
        return "\(clock.string(from: interval.start))–\(clock.string(from: interval.end))"
    }
}

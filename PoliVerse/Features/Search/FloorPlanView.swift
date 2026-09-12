import SwiftUI

/// The official floor plan, with this room highlighted.
///
/// The only room-accurate picture of a building that exists publicly — the
/// geojson has no real footprints, so there is nothing to draw instead. It is
/// a JPEG of a CAD drawing, so it is zoomable rather than scaled to fit: at
/// thumbnail size the room numbers are unreadable.
struct FloorPlanView: View {
    let room: Classroom
    @State private var failed = false

    var body: some View {
        if let url = room.floorPlanURL, !failed {
            Section {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        NavigationLink {
                            ZoomableImage(image: image, title: room.id)
                        } label: {
                            image.resizable().scaledToFit()
                        }
                        .buttonStyle(.plain)
                    case .failure:
                        // Removed rather than left as a broken frame: a plan
                        // that will not load is not worth a permanent gap.
                        Color.clear.frame(height: 0).onAppear { failed = true }
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .listRowInsets(EdgeInsets())
                .background(.white)
            } header: {
                Text("Pianta")
            } footer: {
                Text(room.roomCode == nil
                     ? "Pianta del piano. Tocca per ingrandire."
                     : "L'aula è evidenziata sulla pianta. Tocca per ingrandire.")
            }
        }
    }
}

/// Pinch and pan over a floor plan.
private struct ZoomableImage: View {
    let image: Image
    let title: String

    @State private var zoom: CGFloat = 1
    @State private var committed: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                // Measured rather than taken from `UIScreen.main`, which is the
                // whole device and wrong in a split-screen window.
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * zoom,
                           height: geometry.size.height * zoom)
            }
        }
        .background(.white)
        .gesture(
            MagnifyGesture()
                .onChanged { zoom = min(max(committed * $0.magnification, 1), 6) }
                // Clamped and committed on end, so the next pinch continues
                // from where this one stopped instead of snapping back.
                .onEnded { _ in committed = zoom }
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Adatta") { withAnimation { zoom = 1; committed = 1 } }
                    .disabled(zoom == 1)
            }
        }
    }
}

/// A day at a glance: busy bands over a free track.
///
/// The bands are drawn over one another rather than side by side, because
/// bookings overlap — a lecture and an exam in the same hour are two rows
/// covering the same time, and laying them end to end would stretch the day.
struct OccupancyTimeline: View {
    let bookings: [RoomBooking]
    let day: DateInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.25))
                    ForEach(bookings) { booking in
                        let frame = slot(booking.interval, in: geometry.size.width)
                        if frame.width > 0 {
                            Rectangle()
                                .fill(Color.red.opacity(0.75))
                                .frame(width: frame.width)
                                .offset(x: frame.start)
                        }
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 22)

            HStack {
                Text(RoomBooking.clock.string(from: day.start))
                Spacer()
                Text(RoomBooking.clock.string(from: day.end))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel(bookings.isEmpty
            ? "Nessuna prenotazione"
            : "\(bookings.count) prenotazioni nella giornata")
    }

    private func slot(_ interval: DateInterval, in width: CGFloat) -> (start: CGFloat, width: CGFloat) {
        guard day.duration > 0, let clipped = day.intersection(with: interval) else {
            return (0, 0)
        }
        let scale = width / day.duration
        return (CGFloat(clipped.start.timeIntervalSince(day.start)) * scale,
                CGFloat(clipped.duration) * scale)
    }
}

/// Today's bookings for one room, fetched on demand.
///
/// Its own small fetch rather than a slice of the campus-wide pass: opening
/// one room should not cost 150 requests, and the free-rooms screen's cache
/// is keyed by campus and day, not by room.
struct RoomDayView: View {
    let room: Classroom
    @Environment(FreeRoomsService.self) private var aule

    @State private var bookings: [RoomBooking]?
    @State private var failed = false

    private var day: DateInterval { aule.teachingDay }
    private var isToday: Bool { PoliMiDate.romeCalendar.isDateInToday(day.start) }

    var body: some View {
        Section {
            if let bookings {
                OccupancyTimeline(bookings: bookings, day: day)
                    .listRowSeparator(.hidden)

                let free = RoomSchedule(
                    id: room.id, name: room.id, building: nil, seats: nil,
                    bookings: bookings
                ).freeSlots(in: day)

                ForEach(free, id: \.start) { slot in
                    Label(RoomScheduleView.format(slot), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                ForEach(bookings) { booking in
                    Label(RoomScheduleView.format(booking.interval), systemImage: "person.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if bookings.isEmpty {
                    Text("Nessuna prenotazione oggi.").foregroundStyle(.secondary)
                }
            } else if failed {
                Text("Occupazione non disponibile per quest'aula.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        } header: {
            // Named by the actual day, not "Oggi": the occupancy service
            // remembers whichever date the Aule libere screen was left on,
            // and a header claiming today would quietly misdate the bands.
            Text(isToday ? "Oggi" : day.start.formatted(date: .abbreviated, time: .omitted))
        } footer: {
            if bookings != nil {
                Text("Fasce ricavate dalle lezioni prenotate. Un'aula libera può comunque essere chiusa.")
            }
        }
        .task {
            guard bookings == nil, !failed else { return }
            if let loaded = await aule.bookings(for: room) {
                bookings = loaded
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Occupazione") {
    let day = DateInterval(start: PoliMiDate.time(8, on: .now),
                           end: PoliMiDate.time(20, on: .now))
    return List {
        Section("Oggi") {
            OccupancyTimeline(
                bookings: MockData.roomSchedules(on: .now)[0].bookings, day: day)
        }
    }
    .previewEnvironment()
}

#Preview("Giornata aula") {
    List { RoomDayView(room: MockData.classrooms()[0]) }.previewEnvironment()
}

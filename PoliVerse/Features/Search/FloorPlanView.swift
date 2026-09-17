import SwiftUI

/// The official floor plan, with this room highlighted.
///
/// The only room-accurate picture of a building that exists publicly — the
/// geojson has no real footprints, so there is nothing to draw instead. It is
/// a JPEG of a CAD drawing, so it is zoomable rather than scaled to fit: at
/// thumbnail size the room numbers are unreadable.
struct FloorPlanView: View {
    let room: Classroom
    @State private var image: UIImage?
    @State private var failed = false
    @State private var fullScreen = false
    @State private var loadedURL: URL?

    var body: some View {
        if let url = room.floorPlanURL, !failed {
            Section {
                Group {
                    if let image {
                        Button { fullScreen = true } label: {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pianta dell'aula \(room.id)")
                        .accessibilityHint("Apre la pianta a schermo intero")
                        // Presented from the row, not from the `Section`: a
                        // presentation on the section took the sheet holding
                        // the aula down with it instead of covering it.
                        .fullScreenCover(isPresented: $fullScreen) {
                            FloorPlanFullScreen(image: image, title: room.id)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .listRowInsets(EdgeInsets())
                .background(.white)
                .task(id: url) { await load(url) }
            } header: {
                Text("Pianta")
            } footer: {
                Text(room.roomCode == nil
                     ? "Pianta del piano. Tocca per ingrandire."
                     : "L'aula è evidenziata sulla pianta. Tocca per ingrandire.")
            }
        }
    }

    /// Loaded as a `UIImage` rather than through `AsyncImage`: the zooming
    /// scroll view below is UIKit, and wants the bitmap itself.
    private func load(_ url: URL) async {
        guard loadedURL != url else { return }
        image = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200,
                  let decoded = UIImage(data: data) else { failed = true; return }
            image = await decoded.byPreparingForDisplay() ?? decoded
            loadedURL = url
        } catch {
            // Removed rather than left as a broken frame: a plan that will not
            // load is not worth a permanent gap.
            if !PoliMiAPI.isCancellation(error) { failed = true }
        }
    }
}

/// A floor plan over the whole screen: pinch, pan, double tap.
private struct FloorPlanFullScreen: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var resetToken = 0

    var body: some View {
        NavigationStack {
            ZoomingImageView(image: image, resetToken: resetToken)
                .ignoresSafeArea(edges: .bottom)
                .background(.white)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Adatta") { resetToken += 1 }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi", systemImage: "xmark") { dismiss() }
                    }
                }
        }
    }
}

/// `UIScrollView` zooming, because it is the one that feels right: the zoom
/// follows the fingers, pans with inertia and bounces at the limits. A
/// `MagnifyGesture` over a SwiftUI `ScrollView` competed with the scroll
/// view's own pan and grew the image from its top-left corner.
struct ZoomingImageView: UIViewRepresentable {
    let image: UIImage
    /// Changed to fit the image again.
    var resetToken = 0

    static let maximumZoom: CGFloat = 8

    func makeUIView(context: Context) -> FittingScrollView {
        let scrollView = FittingScrollView(image: image)
        scrollView.delegate = context.coordinator
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: FittingScrollView, context: Context) {
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(resetToken: resetToken) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var resetToken: Int
        init(resetToken: Int) { self.resetToken = resetToken }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? FittingScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? FittingScrollView)?.centreImage()
        }

        /// Zooms in around the tapped point, or back out to fit.
        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? FittingScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            let target = min(scrollView.minimumZoomScale * 3, scrollView.maximumZoomScale)
            let point = recognizer.location(in: scrollView.imageView)
            let size = CGSize(width: scrollView.bounds.width / target,
                              height: scrollView.bounds.height / target)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }
}

/// Keeps the image fitted as the window resizes, and centred when smaller
/// than the screen.
final class FittingScrollView: UIScrollView {
    let imageView: UIImageView
    private var fittedSize: CGSize = .zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)
        contentSize = image.size
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != fittedSize, bounds.width > 0, bounds.height > 0,
              let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }
        let wasFitted = fittedSize == .zero || zoomScale <= minimumZoomScale * 1.01
        fittedSize = bounds.size
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        minimumZoomScale = fit
        maximumZoomScale = max(fit * ZoomingImageView.maximumZoom, 1)
        if wasFitted { zoomScale = fit }
        centreImage()
    }

    func centreImage() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
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
    @Environment(FreeRoomsModel.self) private var aule

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
                bookings: RoomSchedule.samples(on: .now)[0].bookings, day: day)
        }
    }
    .previewEnvironment()
}

#Preview("Giornata aula") {
    List { RoomDayView(room: Classroom.samples()[0]) }.previewEnvironment()
}

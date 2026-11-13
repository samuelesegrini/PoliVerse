#if DEBUG && os(iOS)
import SwiftUI

/// A room's photo full screen (board 5 of the "Cerca · Un'aula" canvas): the photo fitted to
/// the width on the system background, pinch or double-tap to zoom. Glass over it: the
/// room's name on the left; on the right a button that fills the screen with the photo and
/// hides everything else, and the system close button. At the bottom, glass again: whether
/// the room is free, its seats and floor, and Indicazioni.
///
/// Opened with a zoom from the card's photo; swiping down closes it.
struct RoomPhotoViewer: View {
    let room: Classroom
    let image: UIImage
    /// The room's status, as the card has it.
    let status: RoomStatusText
    /// Walking directions to the room's building.
    let directions: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Whether the photo fills the screen, with the chrome hidden.
    @State private var fills = false
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: fills ? .fill : .fit)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .scaleEffect(zoom)
                .offset(pan)
                .gesture(magnify.simultaneously(with: drag))
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        if zoom > 1 { reset() } else { zoom = 2.5; settledZoom = 2.5 }
                    }
                }
                .accessibilityLabel(Text("Foto dell'aula \(room.id)"))
                .accessibilityAddTraits(.isImage)
        }
        .ignoresSafeArea()
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { if !fills { toolbar } }
        .overlay(alignment: .topTrailing) {
            if fills {
                fillButton.padding(.trailing, 16).padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) { if !fills { panel } }
        .animation(.snappy, value: fills)
        .statusBarHidden(fills)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = max(1, min(settledZoom * $0.magnification, 5)) }
            .onEnded { _ in
                settledZoom = zoom
                if zoom <= 1.01 { withAnimation(.snappy) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                pan = CGSize(width: settledPan.width + value.translation.width,
                             height: settledPan.height + value.translation.height)
            }
            .onEnded { _ in settledPan = pan }
    }

    private func reset() {
        zoom = 1; settledZoom = 1; pan = .zero; settledPan = .zero
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack {
            Text("Aula \(room.id)")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    fillButton
                    Button(role: .close) { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("Chiudi"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var fillButton: some View {
        Button {
            withAnimation(.snappy) { reset(); fills.toggle() }
        } label: {
            Image(systemName: fills ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(fills ? "Adatta la foto allo schermo" : "Riempi lo schermo con la foto"))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.headline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(status.tone.colour)
                Spacer(minLength: 8)
                if let until = status.until {
                    Text(until).font(.system(size: 15)).foregroundStyle(.secondary)
                }
            }
            Text(RoomWording.facts(of: room))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DirectionsButton(height: 50, action: directions)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// Indicazioni: the wide accent capsule with the turn arrow.
struct DirectionsButton: View {
    /// 40 points under the compact card, 50 on the room card and the photo.
    var height: CGFloat = 50
    var expands = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Indicazioni", systemImage: "arrow.turn.up.right")
                .font(.system(size: height >= 50 ? 17 : 16, weight: .semibold))
                .labelStyle(DirectionsLabelStyle())
                .foregroundStyle(.white)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(height: height)
                .padding(.horizontal, expands ? 0 : 20)
                .background(.tint, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The symbol and the title eight points apart, as drawn.
private struct DirectionsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

extension RoomStatusText.Tone {
    /// Green when free, red when busy, grey when nothing is known.
    var colour: Color {
        switch self {
        case .free: .freeRoom
        case .busy: .red
        case .unknown: .secondary
        }
    }
}
#endif

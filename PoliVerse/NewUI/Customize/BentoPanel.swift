import SwiftUI

/// Personalizza's panel under the live page, as in Kyo: a bento of tiles, each
/// a small preview of one part of the look, opening its controls in place.
struct BentoPanel: View {
    @Binding var style: TodayStyle
    @Binding var path: [CustomizePage]
    @Binding var arranging: Bool
    @Binding var detent: PresentationDetent

    @Environment(\.shell) private var shell
    @Environment(\.colorScheme) private var scheme
    /// The bento's width, split into thirds.
    @State private var width: CGFloat = 360
    private let gap: CGFloat = 8

    /// The width of a tile spanning some of the three columns.
    private func span(_ columns: Int) -> CGFloat {
        let unit = max((width - gap * 2) / 3, 40)
        return unit * CGFloat(columns) + gap * CGFloat(columns - 1)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        tile(.paper) { PaperTile(paper: style.paper, style: style, showsTitle: false) }
                        tile(.flavor, columns: 2) { flavorPreview }
                    }
                    HStack(spacing: gap) {
                        tile(.widget, columns: 2) {
                            DateHeader(day: shell.day, style: style, size: 34)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 18)
                        }
                        tile(.accessory) { accessoryPreview }
                    }
                    HStack(spacing: gap) {
                        tile(.decoration) { TodayBackgroundView(background: style.background, flavor: style.flavor) }
                        tile(.layout, columns: 2) { layoutPreview }
                    }
                    HStack(spacing: gap) {
                        tile(.cards) { MaterialPreview(material: style.material, style: style).padding(10).padding(.bottom, 14) }
                        tile(.appearance) { appearancePreview }
                        tile(.greeting) {
                            Text(style.greeting.text(for: shell.day, firstName: nil, custom: style.customGreeting))
                                .font(.caption.weight(.semibold))
                                .fontDesign(style.textDesign.design)
                                .multilineTextAlignment(.center)
                                .padding(10)
                                .padding(.bottom, 12)
                        }
                    }
                    HStack(spacing: gap) {
                        tile(.bar) { barPreview }
                        Button { withAnimation(.snappy) { arranging = true } } label: {
                            Label("Disponi", systemImage: "square.stack.3d.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlavorGlossButtonStyle(flavor: style.flavor))
                        .frame(width: span(2))
                        .accessibilityIdentifier("bento-arrange")
                    }
                }
                .padding(12)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 24 } action: { width = $0 }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: CustomizePage.self) { page in
                if case .section(let kind) = page {
                    SectionFormPicker(kind: kind, style: $style,
                                      close: { withAnimation(.snappy) { path.removeAll() } })
                } else if page == .stickerPicker {
                    StickerPicker(remaining: TodayStyle.maxStickers - style.stickers.count) { content in
                        withAnimation(.snappy) { _ = style.addSticker(content) }
                    }
                } else {
                    CustomizeControls(page: page, style: $style, arranging: $arranging,
                                      pickStickers: { path.append(.stickerPicker) },
                                      close: { withAnimation(.snappy) { path.removeAll() } })
                }
            }
        }
        .tint(style.controlTint(scheme))
        // Back at the bento, the panel rests low again so the page and its
        // Fine show. A section's card needs the whole sheet instead.
        .onChange(of: path) { _, path in
            withAnimation(.snappy) {
                if path.isEmpty {
                    detent = BentoPanel.small
                } else if case .section = path.last {
                    detent = .large
                }
            }
        }
    }

    // MARK: Tiles

    private func tile<Preview: View>(_ page: CustomizePage, columns: Int = 1,
                                     @ViewBuilder preview: () -> Preview) -> some View {
        Button { path.append(page) } label: {
            // A fixed frame: a preview's own size must never widen its column.
            preview()
                .frame(width: span(columns), height: 104)
                .clipped()
                // Opaque, so what glows behind the glass sheet stays behind it.
                .background(style.palette(scheme).surface)
                .overlay(alignment: .bottomLeading) {
                    Text(page.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(page == .flavor ? AnyShapeStyle(.white) : AnyShapeStyle(style.accent(scheme)))
                        .padding(9)
                }
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(BentoTileStyle())
        .accessibilityLabel(Text(page.title))
        .accessibilityIdentifier("bento-\(page.id)")
    }

    private var flavorPreview: some View {
        FlavorFlowView(flavor: style.flavor)
            .overlay {
                VStack(spacing: 0) {
                    Text(style.flavor.name).font(.title3.weight(.bold))
                    Text("Flavor").font(.caption2.weight(.semibold)).opacity(0.8)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 5)
            }
    }

    @ViewBuilder
    private var accessoryPreview: some View {
        if style.accessory == .none {
            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(style.accent(scheme))
        } else {
            TodayAccessoryView(style: style)
                .padding(8)
        }
    }

    private var layoutPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(style.visibleSections.prefix(4)) { section in
                HStack(spacing: 6) {
                    Image(systemName: section.kind.systemImage).font(.caption2)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(style.accent(scheme).opacity(0.25))
                        .frame(height: 12)
                }
                .foregroundStyle(style.accent(scheme))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
    }

    /// The bar's buttons as dots: what shows and what does not.
    private var barPreview: some View {
        let accent = style.accent(scheme), off = Color.secondary.opacity(0.2)
        return HStack(spacing: 5) {
            Circle().fill(style.bar.showsProfile ? accent : off).frame(width: 14)
            Circle().fill(accent).frame(width: 14)
            Capsule().fill(style.bar.showsDate ? Color.primary.opacity(0.5) : off).frame(width: 22, height: 8)
            Circle().fill(accent).frame(width: 14)
        }
        .padding(.bottom, 16)
    }

    private var appearancePreview: some View {
        HStack(spacing: 0) {
            style.flavor.ground(dark: false, mode: style.appearance.flavorMode).color
            style.flavor.ground(dark: true, mode: style.appearance.flavorMode).color
        }
        .overlay {
            Image(systemName: style.appearance == .dark ? "moon.fill" : style.appearance == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(style.accent(scheme))
        }
    }
}

/// A tile presses in a little, like Kyo's.
private struct BentoTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

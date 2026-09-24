import PhotosUI
import SwiftUI

/// Where a new look comes from, as the Lock Screen's Add New: a gallery of
/// starting points rather than a form.
///
/// Four ways in along the top — a copy of the look in use, the colours of a
/// photo, a surprise, a blank page — then shelves of looks already made, each
/// with a sentence saying what it is. Every tile is the page exactly as it will
/// be, and picking one goes straight into the editor.
struct NewLookGallery: View {
    /// The look in use, which Copia copies and the paper shelf takes its colour from.
    let current: TodayStyle
    /// Opens the editor on the look picked.
    let pick: (TodayStyle) -> Void

    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    /// A thumbnail's width in the shelves that scroll.
    private static let shelfWidth: CGFloat = 112
    /// A thumbnail's width in the featured grid.
    private static let gridWidth: CGFloat = 108

    /// The view's content.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ways
                    shelf("In primo piano", "Pagine già pensate, diverse da quella che usi.") {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(featured.enumerated()), id: \.offset) { index, look in
                                tile(look, caption: Text(look.displayName(at: index)), width: Self.gridWidth,
                                     id: "customize-new-featured-\(index)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    shelf("Temi", "Carattere, colore, sezioni e decorazioni, scelti insieme.") {
                        rail {
                            ForEach(Array(TodayStyle.presets.enumerated()), id: \.offset) { index, look in
                                tile(look, caption: Text(look.displayName(at: index)), width: Self.shelfWidth,
                                     id: "customize-new-preset-\(index)")
                            }
                        }
                    }
                    shelf("Flavor", "Un colore solo: il resto lo sceglie lui, e puoi cambiarlo dopo.") {
                        rail {
                            ForEach(Flavor.swatches) { swatch in
                                tile(flavorLook(swatch), caption: Text(swatch.name), width: Self.shelfWidth,
                                     id: "customize-new-flavor-\(swatch.flavor.hex)")
                            }
                        }
                    }
                    shelf("Carte e motivi", "La pagina stampata su una carta, o sotto un motivo nel tuo colore.") {
                        rail {
                            ForEach(TodaySheet.all.prefix(12)) { sheet in
                                tile(sheetLook(sheet), caption: Text(sheet.title), width: Self.shelfWidth,
                                     id: "customize-new-\(sheet.id)")
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nuovo stile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("customize-new-cancel")
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let flavor = Flavor.extract(from: image.samplePixels()) {
                    var look = TodayStyle()
                    look.flavor = flavor
                    look.appearance = .tinted
                    look.background = .mesh
                    pick(look)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Ways in

    /// The four ways to start that are not a finished look.
    private var ways: some View {
        HStack(alignment: .top, spacing: 0) {
            Button { pick(copy) } label: { WayLabel(title: "Copia", symbol: "square.on.square") }
                .accessibilityIdentifier("customize-new-duplicate")
            PhotosPicker(selection: $photoItem, matching: .images) { WayLabel(title: "Da una foto", symbol: "photo") }
                .accessibilityIdentifier("customize-new-photo")
            Button { pick(surprise) } label: { WayLabel(title: "Casuale", symbol: "shuffle") }
                .accessibilityIdentifier("customize-new-shuffle")
            Button { pick(TodayStyle()) } label: { WayLabel(title: "Vuota", symbol: "square.dashed") }
                .accessibilityIdentifier("customize-new-blank")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    // MARK: - Shelves

    /// A shelf: its title, a sentence, and its tiles.
    private func shelf<Content: View>(_ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            content()
        }
    }

    /// A shelf's tiles in a row that scrolls.
    private func rail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 10) { content() }
                .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    /// One look to pick: the page as it will be, and its name.
    private func tile(_ look: TodayStyle, caption: Text, width: CGFloat, id: String) -> some View {
        Button { pick(look) } label: {
            VStack(spacing: 6) {
                LookScreen(look: look, scale: width / LookScreen.reference.width, cornerRadius: 60)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width)
            }
            // The page inside takes no touches of its own: the tile is the target.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Looks

    /// Three themes that are not the look in use.
    private var featured: [TodayStyle] {
        Array(TodayStyle.presets.dropFirst().filter { $0.name != current.name }.prefix(3))
    }

    /// The look in use, as a new look beside it.
    private var copy: TodayStyle {
        var look = current
        look.name = current.name.isEmpty ? "" : String("\(current.name) 2".prefix(TodayStyle.nameLimit))
        return look
    }

    /// A theme's page in a random colour, light and typeface.
    private var surprise: TodayStyle {
        var look = TodayStyle.presets.randomElement() ?? TodayStyle()
        look.name = ""
        look.flavor = Flavor.swatches.randomElement()?.flavor ?? look.flavor
        look.appearance = LookEditor.variants.randomElement() ?? look.appearance
        look.dateFont = TodayStyle.DateFont.allCases.randomElement() ?? look.dateFont
        return look
    }

    /// The plain page in one swatch's colour, clearly tinted.
    private func flavorLook(_ swatch: Flavor.Swatch) -> TodayStyle {
        var look = TodayStyle()
        look.name = String(localized: swatch.name)
        look.flavor = swatch.flavor
        look.appearance = .tinted
        return look
    }

    /// The plain page on one paper or under one decoration, in the colour in use.
    private func sheetLook(_ sheet: TodaySheet) -> TodayStyle {
        var look = TodayStyle()
        look.flavor = current.flavor
        look.sheet = sheet
        return look
    }
}

/// One way in: a round glass button and its name. Its own type, nonisolated,
/// because `PhotosPicker` builds its label outside the main actor.
private nonisolated struct WayLabel: View {
    /// The way's name.
    let title: LocalizedStringKey
    /// Its SF Symbol.
    let symbol: String

    /// The view's content.
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 62, height: 62)
                .glassEffect(.regular.interactive(), in: .circle)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

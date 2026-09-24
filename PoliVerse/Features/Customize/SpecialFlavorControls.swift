import SwiftUI

/// A special Flavor's panel: the few knobs it lets the student turn, in its
/// own words, and the way out to a classic Flavor.
///
/// Everything else about the look — its pages, typefaces, surfaces — is the
/// recipe's, so there is nothing else here. The light stays where it is — the
/// swipe on the page and the dots under it — except in Blueprint, which is
/// always dark.
struct SpecialFlavorControls: View {
    /// The look being edited.
    @Binding var style: TodayStyle
    /// Which page the editor shows the Flavor on.
    @Binding var preview: SpecialPreview
    /// Turns the look into a classic Flavor with the recipe's colours and typefaces.
    let duplicateAsClassic: () -> Void

    /// The view's content.
    var body: some View {
        if let special = style.special {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(special.blurb)
                            .font(.subheadline.weight(.semibold))
                        Text("Le forme delle pagine sono sue: tu scegli queste cose.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Anteprima", selection: $preview) {
                        ForEach(SpecialPreview.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("customize-special-preview")
                } header: {
                    Text("Anteprima")
                } footer: {
                    Text("Un Flavor speciale cambia tutte le pagine: guardale qui prima di scegliere.")
                }

                knob(special)

                Section(special == .blueprint ? "Carta e inchiostro" : "Coppia di colori") {
                    HStack(spacing: 14) {
                        ForEach(special.pairs.indices, id: \.self) { index in
                            PairSwatch(pair: special.pairs[index], selected: style.specialSettings.pair == index) {
                                withAnimation(.snappy) { style.specialSettings.pair = index }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Duplica come classico", systemImage: "square.on.square", action: duplicateAsClassic)
                        .accessibilityIdentifier("customize-special-duplicate")
                } footer: {
                    Text("Tieni colori e caratteri e cambi ogni parte. Le forme speciali delle pagine restano qui.")
                }
            }
            .panelTitle(special.title)
        }
    }

    /// The one setting of its own each special Flavor has, in its words.
    @ViewBuilder
    private func knob(_ special: SpecialFlavor) -> some View {
        switch special {
        case .playful:
            Section {
                Picker("Quanto caos", selection: $style.specialSettings.chaos) {
                    ForEach(SpecialSettings.Chaos.allCases) { chaos in
                        Text(chaos.title).tag(chaos)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("customize-special-chaos")
            } header: {
                Text("Quanto caos")
            } footer: {
                Text("Quanto pendono le schede, come adesivi su un quaderno.")
            }
        case .blueprint:
            Section {
                Picker("Griglia", selection: $style.specialSettings.grid) {
                    ForEach(SpecialSettings.Grid.allCases) { grid in
                        Text(grid.title).tag(grid)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("customize-special-grid")
            } header: {
                Text("Griglia")
            } footer: {
                Text("La carta è sempre blu e l’app sempre scura: le linee bianche si leggono solo così.")
            }
        }
    }
}

/// The page Personalizza's editor shows a special Flavor on: Oggi, which is
/// the page being edited, or one of the others, drawn as the app draws them.
enum SpecialPreview: String, CaseIterable, Identifiable {
    /// The four tabs.
    case today, courses, career, search

    /// The page's identity, which is its raw value.
    var id: String { rawValue }

    /// What the tab is called.
    var title: LocalizedStringKey {
        switch self {
        case .today: "Oggi"
        case .courses: "Corsi"
        case .career: "Carriera"
        case .search: "Cerca"
        }
    }
}

/// A colour pair: the page's colour with the one that stands out tucked beside it.
private struct PairSwatch: View {
    /// The pair drawn.
    let pair: ColourPair
    /// Whether it is the pair in use.
    let selected: Bool
    /// Chooses it.
    let pick: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: pick) {
            ZStack(alignment: .leading) {
                Circle().fill(pair.main.color).frame(width: 34, height: 34)
                Circle().fill(pair.second.color).frame(width: 34, height: 34)
                    .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 3) }
                    .offset(x: 20)
            }
            .frame(width: 58, height: 44, alignment: .leading)
            .padding(.horizontal, 4)
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2)
                    .padding(-3)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(pair.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

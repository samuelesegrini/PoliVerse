import SwiftUI

/// A choice between a few options on one capsule of glass, the way Safari
/// switches tab groups: the options side by side as plain text, the chosen one
/// set in bold on a lighter capsule that slides to wherever the student taps.
///
/// Stands in for the system's segmented picker where the choice sits on the
/// page rather than in a form's toolbar, so it reads as part of the glass
/// around it instead of a grey bar laid on top.
struct GlassSegmentedPicker<Value: Hashable, Label: View>: View {
    /// What the choice is, for assistive technologies.
    let title: LocalizedStringKey
    /// The option chosen.
    @Binding var selection: Value
    /// The options, in order.
    let options: [Value]
    /// What each option shows: text, or a symbol.
    @ViewBuilder let label: (Value) -> Label

    /// Groups the sliding capsule's positions, so it moves rather than fades.
    @Namespace private var namespace

    /// A picker over some options.
    ///
    /// - Parameters:
    ///   - title: What the choice is, for assistive technologies.
    ///   - selection: The option chosen.
    ///   - options: The options, in order.
    ///   - label: What each option shows.
    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [Value],
         @ViewBuilder label: @escaping (Value) -> Label) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    /// The view's content.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = option }
                } label: {
                    label(option)
                        .font(.subheadline.weight(chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if chosen {
                                Capsule()
                                    .fill(.primary.opacity(0.1))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

extension GlassSegmentedPicker where Value: CaseIterable, Value.AllCases == [Value] {
    /// A picker over every case of an enumeration.
    ///
    /// - Parameters:
    ///   - title: What the choice is, for assistive technologies.
    ///   - selection: The case chosen.
    ///   - label: What each case shows.
    init(_ title: LocalizedStringKey, selection: Binding<Value>, @ViewBuilder label: @escaping (Value) -> Label) {
        self.init(title, selection: selection, options: Value.allCases, label: label)
    }
}

#Preview {
    @Previewable @State var tab = "Casa"
    GlassSegmentedPicker("Gruppo", selection: $tab, options: ["Privata", "10 pannelli", "Casa"]) { Text($0) }
        .padding()
        .background(LinearGradient(colors: [.mint.opacity(0.4), .teal.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
}

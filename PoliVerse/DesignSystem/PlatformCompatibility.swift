import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The few platform differences the screens would otherwise spell out at every site.
///
/// The app builds for iPhone, iPad and the Mac from one target. Most of SwiftUI is the
/// same everywhere; what is not lives here, so a screen reads the same on both.

/// An image of the platform's own kind.
#if os(iOS)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

/// The system clipboard.
enum Clipboard {
    /// Replaces the clipboard's contents with a string.
    ///
    /// - Parameter string: The text to copy.
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

extension Image {
    /// An image from a platform image.
    ///
    /// - Parameter platformImage: The image.
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension SensoryFeedback {
    /// Picking something up: a medium impact on iPhone; the Mac's trackpad has no
    /// impact, so it gives its alignment tick instead.
    static var lift: SensoryFeedback {
        #if os(iOS)
        .impact(weight: .medium)
        #else
        .alignment
        #endif
    }
}

extension EnvironmentValues {
    /// Closes the detail this view is shown in, when it is shown beside the page rather
    /// than in a sheet; `nil` in a sheet, where the view dismisses itself.
    var closeDetail: (@MainActor () -> Void)? {
        get { self[CloseDetailKey.self] }
        set { self[CloseDetailKey.self] = newValue }
    }
}

/// The key for ``EnvironmentValues/closeDetail``. Written by hand: the `@Entry` macro
/// warns that a closure cannot be compared, and this one is set once per presentation.
private struct CloseDetailKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension View {
    /// A detail — a lecture, a sitting, a deadline — in a sheet on iPhone and iPad, and
    /// in an inspector beside the page on the Mac, where there is room to keep both.
    ///
    /// The detail's own close button reads ``EnvironmentValues/closeDetail`` to shut the
    /// inspector, since an inspector is not dismissed like a sheet.
    ///
    /// - Parameters:
    ///   - item: The detail to show, or `nil` for none.
    ///   - content: The detail's view.
    /// - Returns: The view with the presentation.
    func detailPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        inspector(isPresented: Binding(get: { item.wrappedValue != nil },
                                       set: { if !$0 { item.wrappedValue = nil } })) {
            Group {
                if let value = item.wrappedValue {
                    content(value)
                        .id(value.id)
                        .environment(\.closeDetail, { item.wrappedValue = nil })
                }
            }
            .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
        }
        #else
        sheet(item: item, content: content)
        #endif
    }

    /// Lights the view up under an iPad pointer. The Mac draws its own hover states on
    /// controls, and has no hover effect to ask for.
    ///
    /// - Returns: The view, with the effect on iPhone and iPad.
    func pointerHighlight() -> some View {
        #if os(iOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// A sheet's size on the Mac, where a sheet is only as large as its content asks;
    /// nothing on iPhone and iPad, where the system sizes it.
    ///
    /// - Parameters:
    ///   - width: The ideal width.
    ///   - height: The ideal height.
    /// - Returns: The sized view.
    func macSheetSize(width: CGFloat = 520, height: CGFloat = 640) -> some View {
        #if os(macOS)
        frame(minWidth: width * 0.85, idealWidth: width, minHeight: height * 0.7, idealHeight: height)
        #else
        self
        #endif
    }
}

#if os(macOS)
// The Mac has no navigation bar, so its title modes and placements mean nothing there.
// These stand-ins let the shared screens keep saying what they want on iPhone, and do
// the natural Mac thing instead.

/// The Mac's stand-in for the navigation bar's item namespace.
enum NavigationBarItem {
    /// The Mac's stand-in for the navigation bar's title modes.
    enum TitleDisplayMode {
        case automatic, inline, large
    }
}

extension View {
    /// Does nothing on the Mac, where a window's title sits in its toolbar.
    ///
    /// - Parameter displayMode: Ignored.
    /// - Returns: The view unchanged.
    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }

    /// Does nothing on the Mac, which has no software keyboard to configure.
    ///
    /// - Parameter autocapitalization: Ignored.
    /// - Returns: The view unchanged.
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }

    /// Does nothing on the Mac, which has no software keyboard to configure.
    ///
    /// - Parameter type: Ignored.
    /// - Returns: The view unchanged.
    func keyboardType(_ type: KeyboardType) -> some View {
        self
    }
}

/// The Mac's stand-in for the keyboard's capitalisation modes.
enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

/// The Mac's stand-in for the software keyboard's layouts.
enum KeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad,
         emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

extension ToolbarItemPlacement {
    /// The leading edge of the window's toolbar.
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    /// The trailing edge of the window's toolbar.
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension NSColor {
    // iOS's semantic colours, mapped to the Mac's nearest ones, so `Color(.systemBackground)`
    // reads the same in shared screens.
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemBackground: NSColor { .underPageBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
    static var separator: NSColor { .separatorColor }
    static var systemFill: NSColor { .quaternarySystemFill }
    static var secondarySystemFill: NSColor { .quaternarySystemFill }
    static var systemGray2: NSColor { NSColor(white: 0.68, alpha: 1) }
    static var systemGray3: NSColor { NSColor(white: 0.78, alpha: 1) }
    static var systemGray4: NSColor { NSColor(white: 0.82, alpha: 1) }
    static var systemGray5: NSColor { NSColor(white: 0.90, alpha: 1) }
    static var systemGray6: NSColor { NSColor(white: 0.95, alpha: 1) }
}

extension ListStyle where Self == InsetListStyle {
    /// The Mac's closest list to iOS's inset grouped one.
    static var insetGrouped: InsetListStyle { .inset }
}
#endif

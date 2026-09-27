import SwiftUI
#if os(iOS)
import QuickLook

/// QuickLook preview for a downloaded file.
///
/// QuickLook renders PDFs, Office documents, images and video without the app
/// needing a viewer per format — which matters here, since course material is
/// mostly PDF and slides with the occasional lecture recording.
struct FilePreview: UIViewControllerRepresentable {
    /// The downloaded file to preview.
    let url: URL

    /// Creates the data source Quick Look reads the file from.
    ///
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    /// Creates the Quick Look controller.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The controller.
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    /// Points the controller at a new file when ``url`` changes.
    ///
    /// - Parameters:
    ///   - controller: The controller to update.
    ///   - context: The representable's context.
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    /// Hands Quick Look the one file to preview.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        /// The file to preview.
        var url: URL
        /// Creates the data source.
        ///
        /// - Parameter url: The file to preview.
        init(url: URL) { self.url = url }

        /// One item: the file.
        ///
        /// - Parameter controller: The Quick Look controller.
        /// - Returns: `1`.
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        /// The file at an index.
        ///
        /// - Parameters:
        ///   - controller: The Quick Look controller.
        ///   - index: Always zero.
        /// - Returns: The file.
        func previewController(
            _ controller: QLPreviewController, previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
#else
import Quartz

/// Quick Look preview for a downloaded file, in a sheet sized for the Mac.
struct FilePreview: View {
    /// The downloaded file to preview.
    let url: URL
    /// Closes this sheet.
    @Environment(\.dismiss) private var dismiss

    /// The preview with a bar to close it or open the file in its own app.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button("Apri") { NSWorkspace.shared.open(url) }
                Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Fine") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            QuickLookView(url: url)
        }
        .frame(minWidth: 640, idealWidth: 820, minHeight: 560, idealHeight: 900)
    }
}

/// AppKit's Quick Look view.
private struct QuickLookView: NSViewRepresentable {
    /// The file to show.
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}
#endif

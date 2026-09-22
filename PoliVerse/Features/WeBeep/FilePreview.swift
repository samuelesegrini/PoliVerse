import SwiftUI
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

import Foundation

/// The height each section had the last time it was shown on this phone.
///
/// A section that is waiting holds that height, so the sections under it do not
/// jump when its rows arrive. Heights only: nothing here says what a section
/// contained.
@MainActor
final class ShapeMemory {
    /// The app's memory, kept in the user defaults.
    static let shared = ShapeMemory()

    private static let key = "sectionHeights"
    private let defaults: UserDefaults
    private var heights: [String: Double]
    private var saving: Task<Void, Never>?

    /// Creates a memory.
    ///
    /// - Parameter defaults: Where the heights are kept.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        heights = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    /// The height a section had last time, or `nil` if it was never shown.
    ///
    /// - Parameter name: The section's name.
    func height(for name: String) -> CGFloat? {
        heights[name].map { CGFloat($0) }
    }

    /// Notes a section's height. Written a moment later, so a section that is
    /// still growing costs one write.
    ///
    /// - Parameters:
    ///   - height: The height its content has now.
    ///   - name: The section's name. A fixed word, never data.
    func remember(_ height: CGFloat, for name: String) {
        let rounded = Double(height.rounded())
        guard rounded > 0, abs((heights[name] ?? 0) - rounded) >= 1 else { return }
        heights[name] = rounded
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self.write()
        }
    }

    /// Writes the heights now.
    func write() {
        saving?.cancel()
        defaults.set(heights, forKey: Self.key)
    }

    /// Forgets every height, for sign-out.
    func forget() {
        saving?.cancel()
        heights = [:]
        defaults.removeObject(forKey: Self.key)
    }
}

import Testing

/// Tags for running a slice of the unit tests: a test plan can include or
/// exclude them, and Xcode's navigator groups by them.
extension Tag {
    /// Reads a payload from the Politecnico, WeBeep or a scraped page.
    @Tag static var parsing: Self
    /// Goes through a stubbed transport: requests, retries, partial failures.
    @Tag static var network: Self
    /// Writes to disk, the Keychain or `UserDefaults`.
    @Tag static var persistence: Self
    /// Waits on real time or on concurrent tasks; the first place to look when
    /// a run is flaky.
    @Tag static var timing: Self
}

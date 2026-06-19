import XCTest

extension XCUIApplication {
    /// Launch arguments that make an isolated UI test deterministically start with the sidebar
    /// visible, regardless of the host's persisted NSSplitView collapse (which lives in the bundle's
    /// GLOBAL UserDefaults, not under `AGT_STATE_DIR`). Keep AppKit window restoration enabled so the
    /// main window is ordered forward the same way as a normal launch; the sentinel tells `ContentView`
    /// to apply a test-only AppKit split-view fixup after the window attaches. Production never sees
    /// the sentinel, so its remember-the-collapse behavior is untouched.
    static var sidebarIsolationArguments: [String] {
        ["AGT_UITEST_FORCE_SIDEBAR_VISIBLE"]
    }
}

extension URL {
    /// The persisted single-window snapshot file under an isolated `AGT_STATE_DIR`. Per-window state
    /// now lives in `windows/<uuid>.json` (the `WindowLibrary` layout), not the legacy
    /// `workspaces.json`; a single-window test has exactly one such file. Falls back to the legacy
    /// path until the first window file is written, so callers can poll it the same way they polled
    /// `workspaces.json` before. `self` is the state directory.
    func windowSnapshotFile() -> URL {
        let windowsDir = appendingPathComponent("windows", isDirectory: true)
        if let first = (try? FileManager.default.contentsOfDirectory(at: windowsDir, includingPropertiesForKeys: nil))?
            .filter({ $0.pathExtension == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first {
            return first
        }
        return appendingPathComponent("workspaces.json")
    }
}

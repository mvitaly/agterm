import GhosttyKit
import SwiftUI

/// Bridges one libghostty surface (a `GhosttySurfaceView`) into SwiftUI.
///
/// `makeNSView` returns the cached/created surface view; `dismantleNSView` is a
/// no-op so the surface (and its shell) survives view churn — only an explicit
/// `destroySurface()` frees it. For the Task 1 spike the view is owned by the
/// coordinator; a later task hands ownership to the session.
struct TerminalView: NSViewRepresentable {
    let workingDirectory: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GhosttySurfaceView {
        if let view = context.coordinator.view {
            return view
        }
        let view = GhosttySurfaceView(workingDirectory: workingDirectory)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context _: Context) {
        // Deferred surface creation: makeNSView may have run before the view had
        // a sized window. createSurface is idempotent (guards surface == nil and
        // backing size), so calling it here is safe.
        nsView.createSurface()
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    static func dismantleNSView(_: GhosttySurfaceView, coordinator _: Coordinator) {
        // No-op: the surface outlives the representable. Only an explicit
        // destroySurface() may free it.
    }

    @MainActor
    final class Coordinator {
        var view: GhosttySurfaceView?
    }
}

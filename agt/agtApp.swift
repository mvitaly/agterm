import AppKit
import SwiftUI

@main
struct agtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Window("agt", id: "main") {
            ContentView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Boot libghostty: init, config, app_new, 120fps tick.
        _ = GhosttyApp.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

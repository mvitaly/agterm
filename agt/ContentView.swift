import SwiftUI

/// Task 1 spike: a single hardcoded terminal surface at $HOME. Replaced by the
/// NavigationSplitView sidebar in a later task.
struct ContentView: View {
    var body: some View {
        TerminalView(workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
            .id("spike")
    }
}

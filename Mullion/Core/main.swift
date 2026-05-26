import AppKit

// Top-level code in main.swift is nonisolated by default, but AppKit's main
// entry IS the main thread and AppDelegate is @MainActor. Assume isolation so
// the compiler accepts the calls; runtime correctness is guaranteed by AppKit
// invoking `main` on the main thread.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}

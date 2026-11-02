import AppKit

// AppKit owns lifecycle; SwiftUI renders only the transient popover.
// There is deliberately no WindowGroup or Settings scene.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}

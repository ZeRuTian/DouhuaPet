import AppKit

@MainActor
final class WindowInteractionHarnessDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var moveTimer: Timer?
    private var quitTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: CGRect(x: 300, y: 300, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Douhua Window Interaction Harness"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("HARNESS_READY pid=\(ProcessInfo.processInfo.processIdentifier) frame=\(window.frame)")
        fflush(stdout)

        moveTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window.setFrameOrigin(
                    CGPoint(x: self.window.frame.minX + 120, y: self.window.frame.minY + 40)
                )
                print("HARNESS_MOVED frame=\(self.window.frame)")
                fflush(stdout)
            }
        }
        quitTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = WindowInteractionHarnessDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}

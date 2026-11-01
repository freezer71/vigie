import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SystemMonitor?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        let monitor = SystemMonitor()
        controller = StatusItemController(monitor: monitor)
        monitor.start()
        self.monitor = monitor
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

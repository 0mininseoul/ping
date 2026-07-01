import AppKit

@MainActor
enum ForegroundPresenter {
    static func activateApp() {
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    static func present(_ window: NSWindow?) {
        guard let window else {
            activateApp()
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        Task { @MainActor in
            await Task.yield()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            activateApp()
        }
    }
}

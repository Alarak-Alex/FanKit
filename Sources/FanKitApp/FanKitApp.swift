import AppKit
import FanKitCore
import SwiftUI

@main
struct FanKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = FanStore.shared

    var body: some Scene {
        // The dashboard and the menu bar popover are AppKit windows so the app
        // can run as a menu bar utility with no permanently open window. The
        // only SwiftUI scene is Settings, which supplies the standard app menu.
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

/// Owns the app lifecycle, the main window, and the menu bar item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemController.shared.install()
        Task { @MainActor in
            FanStore.shared.start()
            MainWindowController.shared.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings the dashboard back.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in MainWindowController.shared.show() }
        }
        return true
    }

    /// Hands the fans back to the SMC before the process exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await FanStore.shared.releaseAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Hosts `DashboardView` in a window with a unified, content-extending titlebar.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = DashboardView()
            .environment(FanStore.shared)
            .id(FanStore.shared.languageVersion)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "FanKit"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 800, height: 720))
        window.minSize = NSSize(width: 760, height: 600)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
    }
}

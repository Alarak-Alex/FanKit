import AppKit
import FanKitCore
import Observation
import SwiftUI

/// Owns the menu bar item and its popover.
///
/// `NSStatusItem` is used directly instead of SwiftUI's `MenuBarExtra`: the item
/// needs a fixed, text-driven width so the two-line readout cannot push it off
/// screen, and the popover must behave like a utility panel rather than a window.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var readout: MenuBarReadoutView?
    private var timer: Timer?

    private override init() { super.init() }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "FanKitStatusItem"
        item.behavior = .removalAllowed

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.setButtonType(.momentaryChange)
            button.imagePosition = .noImage
            button.title = ""

            // A custom view draws both lines; an attributed title collapses them.
            let readout = MenuBarReadoutView()
            readout.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(readout)
            NSLayoutConstraint.activate([
                readout.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                readout.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                readout.topAnchor.constraint(equalTo: button.topAnchor),
                readout.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            self.readout = readout
        }

        statusItem = item
        updateLabel()
        observeStore()
    }

    private func observeStore() {
        // The store is `@Observable`, so the label is refreshed on the same
        // cadence as the hardware poll instead of through KVO.
        let timer = Timer(timeInterval: FanKitConstants.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLabel() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateLabel() {
        guard let readout else { return }
        let store = FanStore.shared
        let defaults = UserDefaults.standard
        readout.style = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "")
            ?? .both
        readout.twoLines = defaults.object(forKey: "menuBarTwoLines") as? Bool ?? true
        readout.temperature = store.menuBarTemperature
        readout.rpm = store.totalRPM
        readout.invalidateIntrinsicContentSize()
        statusItem?.length = NSStatusItem.variableLength
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        let popover = self.popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let store = FanStore.shared
        let host = NSHostingController(rootView: AnyView(
            MenuBarPanel()
                .environment(store)
                .id(store.languageVersion)
        ))
        popover.contentViewController = host
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

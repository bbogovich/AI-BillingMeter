import AppKit
import SwiftUI

/// Plain AppKit entry point. A SwiftUI `App` is not used: with no window scenes of its own it
/// opens its `Settings` scene when the Dock icon is clicked, and `MenuBarExtra` gives no access
/// to the status item (see StatusBarController).
@main
enum AIBillingMeterMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(snapshot: Snapshot.outputDirectory != nil)
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.outputDirectory {
            Task { await Snapshot.run(to: dir) }
            return
        }
        // Shown in the Dock as well as the menu bar, so the app stays reachable when the menu
        // bar item is hidden behind the notch or crowded out by other items.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMainMenu()
        statusBar = StatusBarController(model: model) { [weak self] in self?.showSettings() }
    }

    /// Dock icon clicked (or the app opened again while running).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.handleDockClick()
        return false
    }

    @objc func showSettings() {
        let window = settingsWindow ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "AI Billing Meter Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("AIBillingMeterSettings")
            settingsWindow = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func showPanel() { statusBar?.handleDockClick() }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AI Billing Meter",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Show Usage", action: #selector(showPanel), keyEquivalent: "u").target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide AI Billing Meter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AI Billing Meter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "AI Billing Meter", action: nil, keyEquivalent: "").submenu = appMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return main
    }
}

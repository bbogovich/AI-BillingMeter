import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item and the usage panel.
///
/// This replaces SwiftUI's `MenuBarExtra`, which gives no access to its `NSStatusItem`: the app
/// could not tell whether the item was on screen, recreate it, or open the panel from the Dock.
///
/// Why the item goes missing: macOS lays status items out leftwards from the Control Center item,
/// and the most recently added item goes furthest left. On a display with a camera housing
/// ("notch") only the area right of the notch holds status items; an item that would fall under
/// or left of the notch is not drawn, with no error, while the app keeps running. Measured on
/// macOS 26.6 (notch x 771–956 of 1728 pt): ClaudeMon's text item (74–90 pt wide) sat partly under
/// the notch at x 918, and when launched after other menu bar apps it was placed at x 502, left of
/// the notch, and never drawn. Its width changes with its text, so it can cross the edge on any
/// refresh, and any app that adds an item later pushes it further left.
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let showSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var panel: UsagePanel?
    private var hosting: NSView?
    private var outsideClickMonitor: Any?
    /// When the panel last closed. Clicking the item while the panel is open closes the panel on
    /// mouse-down (it loses focus) before the click arrives; the click must not reopen it.
    private var lastClosed = Date.distantPast
    /// Set when the item could not be shown at full width: it then shows the icon only, which
    /// needs less room right of the notch. Cleared on the next launch.
    private var compact = false

    private static let autosaveName = "ClaudeMonStatusItem"

    init(model: AppModel, showSettings: @escaping () -> Void) {
        self.model = model
        self.showSettings = showSettings
        super.init()
        installStatusItem()
        observeLabel()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = [] // Cmd-dragging the item off the bar must not remove it for good.
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityTitle("ClaudeMon")
        }
        statusItem = item
        updateLabel()
    }

    /// Whether the item is drawn where the user can see and click it.
    var isStatusItemVisible: Bool {
        guard let item = statusItem, item.isVisible,
              let button = item.button, let window = button.window, window.isVisible,
              let screen = window.screen else { return false }
        let frame = window.frame
        guard frame.width > 1, screen.frame.intersects(frame) else { return false }
        // On a notched display status items are drawn only right of the notch. The window of an
        // item that did not fit still has a frame, under or left of the notch.
        if let right = screen.auxiliaryTopRightArea {
            return frame.minX >= right.minX - 0.5 && frame.maxX <= right.maxX + 0.5
        }
        return true
    }

    /// Recreates the status item if it is not visible, then, if it is still hidden, shows it as
    /// the icon only. Returns whether it is visible afterwards.
    ///
    /// Recreating helps when the item was lost or left behind by a display change. It cannot win
    /// space from other apps: a new item goes furthest left, the first to be hidden. Hence the
    /// narrower fallback. The menu bar lays items out asynchronously, so each step waits for it.
    @discardableResult
    func reinitializeStatusItemIfHidden() async -> Bool {
        if isStatusItemVisible { return true }
        statusItem?.isVisible = true
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        // macOS before 26 puts a recreated item back at its saved place; start it afresh instead.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(Self.autosaveName)")
        installStatusItem()
        if await settledVisibility() { return true }
        guard !compact, !model.menuBarText.isEmpty else { return false }
        compact = true
        updateLabel()
        return await settledVisibility()
    }

    private func settledVisibility() async -> Bool {
        try? await Task.sleep(for: .milliseconds(400))
        return isStatusItemVisible
    }

    private func observeLabel() {
        withObservationTracking {
            _ = model.menuBarText
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateLabel()
                self?.observeLabel()
            }
        }
    }

    private func updateLabel() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                            accessibilityDescription: "ClaudeMon")
        image?.isTemplate = true
        button.image = image
        let text = compact ? "" : model.menuBarText
        button.toolTip = compact ? "ClaudeMon \(model.menuBarText)" : "ClaudeMon"
        if text.isEmpty {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        } else {
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            button.attributedTitle = NSAttributedString(
                string: " " + text,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)])
            button.imagePosition = .imageLeading
        }
    }

    // MARK: - Panel

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePanel()
    }

    /// The Dock icon was clicked: bring back the menu bar item if it is hidden, and show the panel.
    func handleDockClick() {
        Task {
            await reinitializeStatusItemIfHidden()
            showPanel()
        }
    }

    func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else if Date().timeIntervalSince(lastClosed) > 0.3 {
            showPanel()
        }
    }

    func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        var size = hosting?.fittingSize ?? .zero
        if size.width < 1 || size.height < 1 { size = NSSize(width: 400, height: 600) }
        panel.setFrame(NSRect(origin: panelOrigin(for: size), size: size), display: false)
        panel.makeKeyAndOrderFront(nil)
        statusItem?.button?.highlight(true)
        Task { await model.refreshAll() }
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in Task { @MainActor in self?.closePanel() }
            }
        }
    }

    func closePanel() {
        if panel?.isVisible == true { lastClosed = Date() }
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    /// Top-left corner of the panel: under the menu bar item when it is visible, otherwise at the
    /// right of the menu bar on the screen with the pointer.
    private func panelOrigin(for size: NSSize) -> NSPoint {
        let gap: CGFloat = 4
        if isStatusItemVisible, let frame = statusItem?.button?.window?.frame,
           let screen = statusItem?.button?.window?.screen {
            let visible = screen.visibleFrame
            let x = min(max(frame.midX - size.width / 2, visible.minX + gap), visible.maxX - size.width - gap)
            return NSPoint(x: x, y: frame.minY - gap - size.height)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - size.width - gap * 2, y: visible.maxY - gap - size.height)
    }

    private func makePanel() -> UsagePanel {
        let panel = UsagePanel(
            contentRect: NSRect(x: 0, y: 0, width: 428, height: 600),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true)
        panel.onClose = { [weak self] in self?.closePanel() }

        let content = MenuContentView(model: model)
            .environment(\.showSettings, ShowSettingsAction { [weak self] in
                self?.closePanel()
                self?.showSettings()
            })
        let hosting = NSHostingView(rootView: content)
        // Intrinsic size only: the panel's height is managed by WindowFitter, not by min/max sizes.
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        background.frame.size = hosting.fittingSize
        return panel
    }
}

/// Borderless floating panel styled like a menu bar popover. Closes on Escape or loss of focus.
final class UsagePanel: NSPanel {
    var onClose: (() -> Void)?

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func resignKey() {
        super.resignKey()
        onClose?()
    }
}

/// Opens the Settings window. Injected so `MenuContentView` works outside a SwiftUI scene.
struct ShowSettingsAction {
    let action: () -> Void
    init(_ action: @escaping () -> Void = {}) { self.action = action }
    func callAsFunction() { action() }
}

private struct ShowSettingsKey: EnvironmentKey {
    static let defaultValue = ShowSettingsAction()
}

extension EnvironmentValues {
    var showSettings: ShowSettingsAction {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

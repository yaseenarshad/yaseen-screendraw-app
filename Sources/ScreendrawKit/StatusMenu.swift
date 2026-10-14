import AppKit

/// The menu bar icon and its rows (row 1.13).
///
/// The menu exists with no status item, so a test reads the rows and nothing shows on the screen.
/// `showInMenuBar()` makes the status item.
@MainActor
final class StatusMenu: NSObject {
    /// A fixed name: the key of the position does not depend on the order in which macOS makes the items.
    static let autosaveName = "YaseenScreendraw"

    var onToggleDrawing: () -> Void = {}
    var onToggleClickThrough: () -> Void = {}
    var onClearAll: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    let menu = NSMenu()
    /// The SF Symbol of the menu bar icon. It shows the mode (row 1.14).
    private(set) var symbolName = StatusMenu.symbolName(for: .off)

    private var statusItem: NSStatusItem?
    private let drawRow = NSMenuItem(title: "Start drawing", action: #selector(toggleDrawing), keyEquivalent: "")
    private let clickThroughRow = NSMenuItem(title: "Click through", action: #selector(toggleClickThrough), keyEquivalent: "")
    private let settingsRow = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")

    override init() {
        super.init()

        // The rows are available or not as the mode tells, not as AppKit finds a target.
        menu.autoenablesItems = false
        for row in [drawRow, clickThroughRow, settingsRow] { row.target = self }
        menu.addItem(drawRow)
        menu.addItem(clickThroughRow)
        menu.addItem(row("Clear all", #selector(clearAll)))
        menu.addItem(.separator())
        menu.addItem(settingsRow)
        menu.addItem(.separator())
        menu.addItem(row("Quit", #selector(quit), key: "q"))
        show(.off)
    }

    /// Puts the icon in the menu bar. The first position must be in the settings before this call (row 5.10).
    func showInMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = StatusMenu.autosaveName
        item.menu = menu
        statusItem = item
        showIcon()
    }

    /// One symbol for off, a filled symbol for drawing and click-through.
    static func symbolName(for mode: DrawMode) -> String {
        mode == .off ? "pencil.tip.crop.circle" : "pencil.tip.crop.circle.fill"
    }

    func show(_ mode: DrawMode) {
        drawRow.title = (mode == .off) ? "Start drawing" : "Stop drawing"
        // In mode off, the click-through hotkey shows the toolbar with the pen paused. The row tells
        // the same with its name (D18, rows 4.20 and 4.26).
        clickThroughRow.title = (mode == .off) ? "Show toolbar" : "Click through"
        // The row turns a mode on and off, so it shows that mode with a check mark.
        clickThroughRow.state = (mode == .clickThrough) ? .on : .off
        // The menu bar is below the overlay in mode drawing. A settings window would be below it too (row 5.11).
        settingsRow.isEnabled = (mode != .drawing)
        symbolName = StatusMenu.symbolName(for: mode)
        showIcon()
    }

    /// A row shows its hotkey on its right side, as a menu shows a key equivalent.
    func showHotKey(_ hotKey: HotKeyCombo, for kind: HotKeyKind) {
        let row = (kind == .draw) ? drawRow : clickThroughRow
        row.keyEquivalent = hotKey.menuKeyEquivalent
        row.keyEquivalentModifierMask = hotKey.modifiers
    }

    private func showIcon() {
        // A template image: macOS colours it for a light and for a dark menu bar.
        let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Yaseen Screendraw")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
    }

    private func row(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleDrawing() { onToggleDrawing() }
    @objc private func toggleClickThrough() { onToggleClickThrough() }
    @objc private func clearAll() { onClearAll() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}

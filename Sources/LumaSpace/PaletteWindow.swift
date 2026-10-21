import AppKit
import LumaCore

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌃⌥Space command palette: type to filter, ↑/↓ to choose, ↩ to run, ⎋ to close.
@MainActor
final class PaletteWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let panel: KeyPanel
    private let search = NSSearchField()
    private let table = NSTableView()
    private var shown = Command.all
    var run: (Command) -> Void = { _ in }
    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        search.placeholderString = "Type a command…"
        search.font = .systemFont(ofSize: 18)
        search.focusRingType = .none
        search.delegate = self
        table.addTableColumn(NSTableColumn(identifier: .init("c")))
        table.headerView = nil
        table.rowHeight = 30
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(runSelected)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        let stack = NSStackView(views: [search, scroll])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
    }

    /// Centres on the output window's screen (the glasses when connected).
    func show(over window: NSWindow?) {
        search.stringValue = ""
        filter()
        let frame = window?.frame ?? NSScreen.main?.frame ?? .zero
        panel.setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.midY - 180))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    func hide() { panel.orderOut(nil) }

    /// Types `query` and runs the top match (used by the verification demo).
    func runQuery(_ query: String) {
        search.stringValue = query
        filter()
        runSelected()
    }

    func windowDidResignKey(_ n: Notification) { hide() }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = shown[row]
        let title = NSTextField(labelWithString: c.title)
        title.font = .systemFont(ofSize: 15)
        let key = NSTextField(labelWithString: Hotkeys.label(for: c) ?? "")
        key.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        key.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [title, spacer, key])
        return row
    }

    func controlTextDidChange(_ n: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): step(1); return true
        case #selector(NSResponder.moveUp(_:)): step(-1); return true
        case #selector(NSResponder.insertNewline(_:)): runSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): hide(); return true
        default: return false
        }
    }

    private func filter() {
        shown = paletteMatches(search.stringValue, in: Command.all)
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func step(_ d: Int) {
        guard !shown.isEmpty else { return }
        let r = min(max(table.selectedRow + d, 0), shown.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func runSelected() {
        let r = table.selectedRow
        guard r >= 0, r < shown.count else { return }
        let c = shown[r]
        hide()
        run(c)
    }
}

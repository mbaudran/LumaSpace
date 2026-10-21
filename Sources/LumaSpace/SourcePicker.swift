import AppKit
import LumaCore

/// Floating searchable list of windows and displays. ↑/↓ choose, ↩ adds, ⎋ cancels.
@MainActor
final class SourcePicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var panel: NSPanel?
    private let table = NSTableView()
    private let search = NSSearchField()
    private var all: [PanelSource] = []
    private var shown: [PanelSource] = []
    private var completion: ((PanelSource?) -> Void)?

    func present(sources: [PanelSource], over window: NSWindow?, completion: @escaping (PanelSource?) -> Void) {
        close(with: nil)
        all = sources
        shown = sources
        self.completion = completion

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.level = .screenSaver
        p.isReleasedWhenClosed = false

        search.placeholderString = "Add a window or display"
        search.delegate = self
        search.font = .systemFont(ofSize: 16)
        let col = NSTableColumn(identifier: .init("name"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(choose)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let stack = NSStackView(views: [search, scroll])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 14, bottom: 14, right: 14)
        p.contentView = stack
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

        if let frame = window?.frame {
            p.setFrameOrigin(NSPoint(x: frame.midX - 260, y: frame.midY - 190))
        } else {
            p.center()
        }
        panel = p
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(search)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = shown[row]
        let icon = if case .display = s { "display" } else { "macwindow" }
        let label = NSTextField(labelWithString: s.label)
        label.lineBreakMode = .byTruncatingTail
        let image = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage())
        let row = NSStackView(views: [image, label])
        row.spacing = 8
        return row
    }

    func controlTextDidChange(_ n: Notification) {
        let q = search.stringValue.lowercased()
        shown = q.isEmpty ? all : all.filter { $0.label.lowercased().contains(q) }
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): step(1); return true
        case #selector(NSResponder.moveUp(_:)): step(-1); return true
        case #selector(NSResponder.insertNewline(_:)): choose(); return true
        case #selector(NSResponder.cancelOperation(_:)): close(with: nil); return true
        default: return false
        }
    }

    private func step(_ d: Int) {
        guard !shown.isEmpty else { return }
        let r = min(max(table.selectedRow + d, 0), shown.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func choose() {
        let r = table.selectedRow
        close(with: r >= 0 && r < shown.count ? shown[r] : nil)
    }

    private func close(with s: PanelSource?) {
        panel?.orderOut(nil)
        panel = nil
        let c = completion
        completion = nil
        c?(s)
    }
}

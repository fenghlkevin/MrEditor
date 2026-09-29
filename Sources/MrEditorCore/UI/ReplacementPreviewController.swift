import AppKit

struct ReplacementPreview {
    let rows: [String]
    var details: [ReplacementDetail] = []
    let limited: Bool
    let apply: (Set<Int>) -> Bool
    let undo: () -> Void
    var canUndo: () -> Bool = { true }
}

/// A snapshot: applying checks the document revision before changing any text.
final class ReplacementPreviewController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let preview: ReplacementPreview
    private var included: Set<Int>
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let applyButton = NSButton()
    private let undoButton = NSButton()
    private var applied = false

    init(preview: ReplacementPreview) {
        self.preview = preview
        included = Set(preview.rows.indices)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 390),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.delegate = self
        panel.title = L("search.preview")
        panel.minSize = NSSize(width: 420, height: 250)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.delegate = self; table.dataSource = self
        scroll.documentView = table
        applyButton.title = L("search.applySelected")
        applyButton.target = self; applyButton.action = #selector(applyChanges)
        undoButton.title = L("search.undoReplacement")
        undoButton.target = self; undoButton.action = #selector(undoChanges)
        undoButton.isEnabled = false
        let all = NSButton(title: L("search.selectAll"), target: self, action: #selector(selectAllRows))
        let none = NSButton(title: L("search.selectNone"), target: self, action: #selector(selectNoRows))
        let close = NSButton(title: L("search.closePreview"), target: self, action: #selector(closePreview))
        let buttons = NSStackView(views: [all, none, undoButton, applyButton, close])
        buttons.spacing = 8
        let stack = NSStackView(views: [status, scroll, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func numberOfRows(in tableView: NSTableView) -> Int { preview.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let button = NSButton(checkboxWithTitle: preview.rows[row], target: self, action: #selector(toggleRow(_:)))
        button.tag = row; button.state = included.contains(row) ? .on : .off
        button.isEnabled = !applied
        button.toolTip = preview.rows[row]
        return button
    }
    private func refresh() {
        status.stringValue = L("search.previewCount", included.count, preview.rows.count)
            + (preview.limited ? " · " + L("search.previewLimit") : "")
        applyButton.isEnabled = !applied && !included.isEmpty
        table.reloadData()
    }
    @objc private func closePreview() {
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closePreview(); return false }
    @objc private func toggleRow(_ button: NSButton) {
        if button.state == .on { included.insert(button.tag) } else { included.remove(button.tag) }
        refresh()
    }
    @objc private func selectAllRows() { guard !applied else { return }; included = Set(preview.rows.indices); refresh() }
    @objc private func selectNoRows() { guard !applied else { return }; included = []; refresh() }
    @objc private func applyChanges() {
        guard preview.apply(included) else {
            status.stringValue = L("search.previewStale"); applyButton.isEnabled = false; return
        }
        applied = true; refresh()
        status.stringValue = L("search.applied", included.count)
        undoButton.isEnabled = true
    }
    @objc private func undoChanges() {
        preview.undo(); undoButton.isEnabled = false
        status.stringValue = L("search.undone")
    }
}

struct ReplacementDetail {
    var documentID: String = ""
    var documentName: String = ""
    let line: Int
    let source: String
    let range: NSRange
    let replacement: String
}

import AppKit

final class RemoteFilePickerController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onClose: (() -> Void)?
    var onOpen: ((RemoteSession, Bool) -> Void)?
    var onInitialDirectory: ((String) -> Void)?
    private var session: RemoteSession?
    private let initialPath: String
    private let legacy: Bool
    private let location = NSTextField()
    private let search = NSSearchField()
    private let sort = NSPopUpButton()
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let follow = NSButton(checkboxWithTitle: L("ssh.follow"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private lazy var up = button("ssh.parentDirectory", #selector(goUp))
    private lazy var go = button("ssh.goDirectory", #selector(goToDirectory))
    private lazy var refreshButton = button("ssh.refreshDirectory", #selector(refresh))
    private lazy var openButton = button("ssh.openFile", #selector(openSelection))
    private var currentDirectory = ""
    private var listing: RemoteDirectory.Listing?
    private var visible: [RemoteDirectory.Entry] = []
    private var request = 0
    private var busy = false
    private var closed = false
    private let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
        return formatter
    }()

    init(session: RemoteSession, path: String, legacy: Bool = false, follow: Bool) {
        self.session = session; initialPath = path; self.legacy = legacy
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 530),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("ssh.chooseRemoteFile"); window.minSize = NSSize(width: 620, height: 420)
        super.init(window: window)
        window.delegate = self; window.center()
        self.follow.state = follow ? .on : .off
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) {
        closed = true; request += 1; session = nil; onOpen = nil; onInitialDirectory = nil
        listing = nil; visible = []; onClose?(); onClose = nil
    }
    private func button(_ key: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: L(key), target: self, action: action); b.bezelStyle = .rounded; return b
    }
    private func build() {
        guard let content = window?.contentView, let session else { return }
        let identity = NSTextField(labelWithString: L("ssh.serverConnected", session.target.host))
        identity.textColor = .secondaryLabelColor
        location.stringValue = initialPath; location.target = self; location.action = #selector(goToDirectory)
        location.setAccessibilityLabel(L("ssh.currentDirectory"))
        location.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let pathRow = NSStackView(views: [up, location, go, refreshButton]); pathRow.spacing = 8
        search.placeholderString = L("ssh.filenameFilter"); search.delegate = self
        search.setAccessibilityLabel(L("ssh.filenameFilter"))
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sort.addItems(withTitles: [L("ssh.sortNewest"), L("ssh.sortName")])
        sort.target = self; sort.action = #selector(filterChanged)
        let tools = NSStackView(views: [search, sort]); tools.spacing = 8
        for (id, title, width) in [("name", "ssh.fileName", 390.0), ("size", "ssh.fileSize", 85.0), ("modified", "ssh.fileModified", 170.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = L(title); column.width = width
            column.minWidth = id == "name" ? 160 : 70
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 28
        table.allowsMultipleSelection = false; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self; table.doubleAction = #selector(openSelection)
        table.setAccessibilityLabel(L("ssh.chooseRemoteFile"))
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        status.textColor = .secondaryLabelColor; status.setAccessibilityRole(.staticText)
        let statusRow = NSStackView(views: [spinner, status]); statusRow.spacing = 8
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [button("ssh.backConnection", #selector(cancel)), spacer, follow, openButton]); footer.spacing = 10
        openButton.keyEquivalent = "\r"; openButton.isEnabled = false
        let stack = NSStackView(views: [identity, NSTextField(labelWithString: L("ssh.currentDirectory")), pathRow, tools, scroll, statusRow, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        for view in [pathRow, tools, scroll, statusRow, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        window?.initialFirstResponder = table
    }
    func start() {
        guard let session else { return }
        let token = beginRequest(path: initialPath)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let resolved = try session.browserLocation(path: self?.initialPath ?? session.target.path, legacy: self?.legacy ?? false)
                let listing = try session.listDirectory(resolved.directory)
                DispatchQueue.main.async {
                    guard let self, self.request == token, !self.closed else { return }
                    self.apply(listing, path: resolved.directory, selected: resolved.selectedName)
                    self.onInitialDirectory?(resolved.directory)
                }
            } catch { DispatchQueue.main.async { self?.fail(error, token: token) } }
        }
    }
    @discardableResult private func beginRequest(path: String) -> Int {
        request += 1; currentDirectory = path; location.stringValue = path
        listing = nil; visible = []; table.reloadData()
        setBusy(true); status.stringValue = L("ssh.loadingDirectory")
        return request
    }
    private func load(_ path: String, selected: String? = nil) {
        guard let session else { return }
        do { try RemoteDirectory.validate(path) } catch { status.stringValue = error.localizedDescription; return }
        let token = beginRequest(path: path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let listing = try session.listDirectory(path)
                DispatchQueue.main.async {
                    guard let self, self.request == token, !self.closed else { return }
                    self.apply(listing, path: path, selected: selected)
                }
            } catch { DispatchQueue.main.async { self?.fail(error, token: token) } }
        }
    }
    private func apply(_ listing: RemoteDirectory.Listing, path: String, selected: String?) {
        currentDirectory = path; location.stringValue = path; self.listing = listing
        setBusy(false); rebuild(selected: selected)
    }
    private func fail(_ error: Error, token: Int) {
        guard request == token, !closed else { return }
        setBusy(false); status.stringValue = RemoteWindowController.describe(error)
    }
    private var selectedEntry: RemoteDirectory.Entry? {
        visible.indices.contains(table.selectedRow) ? visible[table.selectedRow] : nil
    }
    private func setBusy(_ value: Bool) {
        busy = value
        value ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        table.isEnabled = !value; search.isEnabled = !value; sort.isEnabled = !value
        // Navigation remains available after errors; in-flight responses are invalidated by request IDs.
        up.isEnabled = !value && currentDirectory != "/"
        go.isEnabled = !value; location.isEnabled = !value; refreshButton.isEnabled = !value
        updateSelection()
    }
    private func rebuild(selected: String?) {
        visible = RemoteDirectory.sorted(listing?.entries ?? [], query: search.stringValue, byName: sort.indexOfSelectedItem == 1)
        table.reloadData(); table.deselectAll(nil)
        if let selected, let row = visible.firstIndex(where: { $0.name == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
        }
        updateSelection()
    }
    private func updateSelection() {
        let entry = selectedEntry
        openButton.title = L(entry?.kind == .directory ? "ssh.enterDirectory" : "ssh.openFile")
        openButton.isEnabled = !busy && (entry?.canOpen == true || entry?.kind == .directory)
        guard !busy else { return }
        let message: String
        if let entry {
            if entry.isCompressed { message = L("ssh.compressedRemote") }
            else if entry.kind == .other { message = L("ssh.unsupportedRemoteEntry") }
            else { message = L("ssh.selectedFile", entry.name) }
        } else if visible.isEmpty { message = L(search.stringValue.isEmpty ? "ssh.emptyDirectory" : "ssh.noMatchingFiles") }
        else { message = L("ssh.selectFileHint") }
        status.stringValue = (listing?.truncated == true ? L("ssh.directoryLimited", RemoteDirectory.entryLimit) + " " : "") + message
    }
    @objc private func goUp() { search.stringValue = ""; load(RemoteDirectory.parent(currentDirectory)) }
    @objc private func goToDirectory() { search.stringValue = ""; load(location.stringValue) }
    @objc private func refresh() { load(currentDirectory, selected: selectedEntry?.name) }
    @objc private func filterChanged() { rebuild(selected: selectedEntry?.name) }
    func controlTextDidChange(_ obj: Notification) { filterChanged() }
    @objc private func cancel() { close() }
    @objc private func openSelection() {
        guard !busy, let entry = selectedEntry, let session else { return }
        let path = RemoteDirectory.child(entry.name, in: currentDirectory)
        if entry.kind == .directory { search.stringValue = ""; load(path); return }
        guard entry.canOpen else { return }
        request += 1; let token = request; let shouldFollow = follow.state == .on
        setBusy(true); status.stringValue = L("ssh.openingFile")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let file = try session.selectingFile(path)
                DispatchQueue.main.async {
                    guard let self, !self.closed, self.request == token else { return }
                    self.onOpen?(file, shouldFollow); self.close()
                }
            } catch { DispatchQueue.main.async { self?.fail(error, token: token) } }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row) else { return nil }
        let entry = visible[row]
        let text = NSTextField(labelWithString: ""); text.lineBreakMode = .byTruncatingMiddle
        switch tableColumn?.identifier.rawValue {
        case "name":
            text.stringValue = entry.name; text.toolTip = entry.name
            let icon = NSImageView(image: NSImage(systemSymbolName: entry.kind == .directory ? "folder" : "doc.text", accessibilityDescription: nil) ?? NSImage())
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let stack = NSStackView(views: [icon, text]); stack.spacing = 8
            if !entry.canOpen && entry.kind != .directory { text.textColor = .secondaryLabelColor }
            return stack
        case "size": text.stringValue = entry.kind == .directory ? "—" : entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        default: text.stringValue = entry.modified.map(formatter.string(from:)) ?? "—"
        }
        text.textColor = .secondaryLabelColor
        return text
    }
}

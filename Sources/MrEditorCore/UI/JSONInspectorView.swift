import AppKit

final class JSONTaskToken {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

/// Only visible outline rows become views. Wide containers have pages of 500 children.
final class JSONInspectorView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Row {
        let id: Int
        let ordinal: Int
        let page: Bool
        var children: [Row]?
        init(_ id: Int, ordinal: Int = 0, page: Bool = false) { self.id = id; self.ordinal = ordinal; self.page = page }
    }
    private let outline = NSOutlineView()
    private let status = NSTextField(labelWithString: "正在后台解析 JSON…")
    private let format = NSButton(title: "格式化", target: nil, action: nil)
    private var index: JSONIndex?
    private var root: Row?
    private var token = JSONTaskToken()
    private let queue = DispatchQueue(label: "mreditor.json", qos: .userInitiated)
    var onClose: (() -> Void)?
    var onReveal: ((Int) -> Void)?
    var onFormatted: ((URL) -> Void)?
    private var formatWhenReady = false
    private var outputName = "formatted.json"
    override init(frame: NSRect) {
        super.init(frame: frame)
        let refresh = NSButton(title: "刷新", target: self, action: #selector(refreshData))
        format.target = self; format.action = #selector(formatJSON); format.isEnabled = false
        let close = NSButton(title: "返回原始", target: self, action: #selector(close))
        let header = NSStackView(views: [refresh, format, close]); header.spacing = 8
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("json")); column.width = 420; column.minWidth = 100; column.resizingMask = .autoresizingMask
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.autoresizesOutlineColumn = false
        outline.autoresizingMask = [.width]
        outline.addTableColumn(column); outline.outlineTableColumn = column; outline.headerView = nil
        outline.rowHeight = 24; outline.indentationPerLevel = 18; outline.delegate = self; outline.dataSource = self
        outline.usesAlternatingRowBackgroundColors = true
        scroll.documentView = outline
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        for v in [header, status, scroll] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            status.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    var onRefresh: (() -> Void)?
    @objc private func refreshData() { onRefresh?() }
    @objc private func close() { cancel(); onClose?() }
    func cancel() { token.cancel() }
    func sourceDidChange() {
        cancel(); format.isEnabled = false; status.stringValue = "正在等待输入完成…"
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !token.cancelled, outline.selectedRow >= 0,
              let row = outline.item(atRow: outline.selectedRow) as? Row, !row.page,
              let index else { return }
        let node = index.nodes[row.id]
        onReveal?(node.key?.lowerBound ?? node.start)
    }
    deinit { token.cancel() }
    func load(url: URL?, text: String?, formatImmediately: Bool = false, recordData: Data? = nil, recordRange: Range<Int>? = nil, dataProvider: ((_ cancelled: () -> Bool) throws -> Data)? = nil) {
        token.cancel(); outline.deselectAll(nil); token = JSONTaskToken(); let job = token
        formatWhenReady = formatImmediately
        outputName = (url?.deletingPathExtension().lastPathComponent ?? "JSON") + ".formatted.json"
        index = nil; root = nil; outline.reloadData(); format.isEnabled = false
        status.stringValue = "正在后台解析 JSON…（可返回原始视图取消）"
        queue.async { [weak self] in
            do {
                let data: Data
                if let dataProvider { data = try dataProvider { job.cancelled } }
                else if let recordData, let recordRange { data = recordData.subdata(in: recordRange) }
                else if let text { data = Data(text.utf8) }
                else if let url { data = try Data(contentsOf: url, options: .alwaysMapped) }
                else { throw JSONIndex.Invalid(offset: 0) }
                let parsed = try JSONIndex.parse(data, cancelled: { job.cancelled })
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled else { return }
                    self.index = parsed; self.root = Row(0); self.format.isEnabled = true
                    self.status.stringValue = "\(parsed.nodes.count) 个节点 · 每页 500 项 · 编辑后自动更新"
                    self.outline.reloadData(); self.outline.expandItem(self.root)
                    if self.formatWhenReady { self.formatJSON() }
                }
            } catch { DispatchQueue.main.async { [weak self] in if !job.cancelled { self?.status.stringValue = error.localizedDescription } } }
        }
    }
    @objc private func formatJSON() {
        guard let index else { return }
        let job = token
        let filename = outputName
        format.isEnabled = false; status.stringValue = "正在生成格式化副本，原文件不会改动…"
        queue.async { [weak self] in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mreditor-json-" + UUID().uuidString)
            let url = folder.appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try index.formatted(to: url, cancelled: { job.cancelled })
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled else { try? FileManager.default.removeItem(at: folder); return }
                    self.format.isEnabled = true; self.status.stringValue = "格式化副本已生成，可另存到目标位置。"
                    self.onFormatted?(url)
                }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                DispatchQueue.main.async { [weak self] in if !job.cancelled { self?.format.isEnabled = true; self?.status.stringValue = error.localizedDescription } }
            }
        }
    }
    private func children(_ row: Row) -> [Row] {
        if let cached = row.children { return cached }
        guard let index else { return [] }
        var id = row.page ? row.id : index.nodes[row.id].first
        var ordinal = row.page ? row.ordinal : 0
        var result: [Row] = []
        while id >= 0 && result.count < 500 {
            result.append(Row(id, ordinal: ordinal)); id = index.nodes[id].next; ordinal += 1
        }
        if id >= 0 { result.append(Row(id, ordinal: ordinal, page: true)) }
        row.children = result; return result
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let row = item as? Row else { return root == nil ? 0 : 1 }
        return children(row).count
    }
    func outlineView(_ outlineView: NSOutlineView, child: Int, ofItem item: Any?) -> Any {
        if let row = item as? Row { return children(row)[child] }
        return root!
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let row = item as? Row, let index else { return false }
        return row.page || index.nodes[row.id].count > 0
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? Row, let index else { return nil }
        let id = NSUserInterfaceItemIdentifier("json.cell")
        let label = outlineView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        label.identifier = id; label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        if row.page { label.stringValue = "继续展开第 \(row.ordinal + 1) 项起的内容…"; label.textColor = .secondaryLabelColor; return label }
        let n = index.nodes[row.id]
        let key = n.key.map { index.text($0) + ": " } ?? (row.id == 0 ? "" : "[\(row.ordinal)]: ")
        let value = n.kind == 123 ? "{ }  \(n.count) 个字段" : n.kind == 91 ? "[ ]  \(n.count) 项" : index.text(n.start..<n.end)
        label.stringValue = key + value
        label.textColor = n.kind == 34 ? .systemGreen : n.kind == 123 || n.kind == 91 ? .labelColor : .systemBlue
        let styled = NSMutableAttributedString(string: key + value, attributes: [.font: label.font!, .foregroundColor: label.textColor ?? NSColor.labelColor])
        if !key.isEmpty { styled.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: NSRange(location: 0, length: (key as NSString).length)) }
        label.attributedStringValue = styled
        label.toolTip = label.stringValue
        return label
    }
}

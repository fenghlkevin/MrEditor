import AppKit

/// A virtualized table decodes only requested rows. NDJSON parses only the selected record.
final class RecordInspectorView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let mode: StructuredMode
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "正在读取…")
    private let detail = NSTextView()
    private let detailScroll = NSScrollView()
    private let headerToggle = NSButton(checkboxWithTitle: "首条记录作为表头", target: nil, action: nil)
    private let formatAll = NSButton(title: "格式化", target: nil, action: nil)
    private var outputName = "NDJSON.formatted.json"
    private let search = NSSearchField()
    private let previous = NSButton(title: "上一组列", target: nil, action: nil)
    private let next = NSButton(title: "下一组列", target: nil, action: nil)
    private var index: RecordIndex?
    private var token = JSONTaskToken()
    private var searchToken = JSONTaskToken()
    private let queue = DispatchQueue(label: "mreditor.records", qos: .userInitiated)
    private var displayedRows: [Int]?
    private var rowCache: [Int: [String]] = [:]
    private var pendingRows = Set<Int>()
    private var columnRevision = 0
    private let searchQueue = DispatchQueue(label: "mreditor.records.search", qos: .userInitiated)
    private var selectedColumn = 0
    private var columnOffset = 0
    private let pageSize = 100
    private var jsonDetail: JSONInspectorView?
    private var selectionRevision = 0
    var onClose: (() -> Void)?
    var onReveal: ((Int) -> Void)?
    private var restoringSelection = false
    var onRefresh: (() -> Void)?
    init(mode: StructuredMode) { self.mode = mode; super.init(frame: .zero); setup() }
    required init?(coder: NSCoder) { fatalError() }
    private func setup() {
        let refresh = NSButton(title: "刷新", target: self, action: #selector(refreshData))
        let close = NSButton(title: "返回原始", target: self, action: #selector(close))
        headerToggle.target = self; headerToggle.action = #selector(changeHeader)
        headerToggle.state = .on; headerToggle.isHidden = mode == .ndjson
        formatAll.target = self; formatAll.action = #selector(formatRecords)
        formatAll.isHidden = mode != .ndjson; formatAll.isEnabled = false
        formatAll.toolTip = "将全部记录格式化为新的 JSON 数组文件，保留原始 NDJSON。"
        let header = NSStackView(views: [refresh, headerToggle, formatAll, close]); header.spacing = 8
        search.placeholderString = "搜索记录，回车筛选"; search.target = self; search.action = #selector(filterRows)
        search.sendsSearchStringImmediately = false; search.sendsWholeSearchString = true
        previous.target = self; previous.action = #selector(previousColumns)
        next.target = self; next.action = #selector(nextColumns)
        let paging = NSStackView(views: [previous, next]); paging.spacing = 8; paging.isHidden = mode == .ndjson
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
        table.delegate = self; table.dataSource = self; table.rowHeight = 25
        table.usesAlternatingRowBackgroundColors = true; table.allowsColumnResizing = true; table.allowsColumnReordering = mode != .ndjson
        table.target = self; table.action = #selector(selectCell)
        table.columnAutoresizingStyle = mode == .ndjson ? .lastColumnOnlyAutoresizingStyle : .noColumnAutoresizing
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = mode != .ndjson
        detail.isEditable = false; detail.isRichText = false; detail.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detail.textContainerInset = NSSize(width: 10, height: 8)
        detailScroll.documentView = detail; detailScroll.hasVerticalScroller = true
        for v in [header, search, paging, status, scroll, detailScroll] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            search.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            paging.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6), paging.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            status.topAnchor.constraint(equalTo: paging.bottomAnchor, constant: 6), status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 1), detailScroll.heightAnchor.constraint(equalTo: heightAnchor, multiplier: mode == .ndjson ? 0.45 : 0.23),
            detailScroll.leadingAnchor.constraint(equalTo: leadingAnchor), detailScroll.trailingAnchor.constraint(equalTo: trailingAnchor), detailScroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        detail.string = mode == .ndjson ? "选择一条记录查看 JSON 树；错误记录会显示原因。" : "点击单元格查看、选择并复制内容（超长字段最多预览 1 MiB）。"
    }
    func cancel() { token.cancel(); searchToken.cancel(); selectionRevision += 1; jsonDetail?.cancel() }
    func sourceDidChange() {
        cancel(); formatAll.isEnabled = false; jsonDetail?.sourceDidChange()
        status.stringValue = "正在等待输入完成…"
    }
    deinit { cancel() }
    @objc private func close() { cancel(); onClose?() }
    @objc private func refreshData() { onRefresh?() }
    func load(url: URL?, text: String?, dataProvider: ((_ cancelled: () -> Bool) throws -> Data)? = nil) {
        let previousSelection = table.selectedRow
        cancel(); token = JSONTaskToken(); let job = token
        formatAll.isEnabled = false
        outputName = (url?.deletingPathExtension().lastPathComponent ?? "NDJSON") + ".formatted.json"
        index = nil; displayedRows = nil; rowCache.removeAll(); pendingRows.removeAll(); columnOffset = 0
        jsonDetail?.removeFromSuperview(); jsonDetail = nil; table.reloadData()
        status.stringValue = "正在后台索引 \(mode.displayName)…可返回原始取消"
        let mode = self.mode
        queue.async { [weak self] in
            do {
                let data: Data
                if let dataProvider { data = try dataProvider { job.cancelled } }
                else { data = try text.map { Data($0.utf8) } ?? url.map { try Data(contentsOf: $0, options: .alwaysMapped) } ?? Data() }
                let parsed = try RecordIndex.parse(data, mode: mode, cancelled: { job.cancelled })
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled else { return }
                    self.index = parsed; self.formatAll.isEnabled = true; self.configureColumns(); self.filterRows()
                    if self.search.stringValue.isEmpty, previousSelection >= 0, previousSelection < self.numberOfRows(in: self.table) {
                        self.restoringSelection = true
                        self.table.selectRowIndexes(IndexSet(integer: previousSelection), byExtendingSelection: false)
                        self.restoringSelection = false
                    }
                }
            } catch { DispatchQueue.main.async { [weak self] in if !job.cancelled { self?.status.stringValue = error.localizedDescription } } }
        }
    }
    @objc private func formatRecords() {
        guard mode == .ndjson, let index else { return }
        let job = token, name = outputName
        formatAll.isEnabled = false
        status.stringValue = "正在格式化全部记录为 JSON 数组，原文件保持不变…"
        queue.async { [weak self] in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mreditor-ndjson-" + UUID().uuidString)
            let output = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try index.formattedJSON(to: output, cancelled: { job.cancelled })
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled else { try? FileManager.default.removeItem(at: folder); return }
                    self.formatAll.isEnabled = true; self.onFormatted?(output)
                }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled else { return }
                    self.formatAll.isEnabled = true; self.status.stringValue = error.localizedDescription
                    let alert = NSAlert(); alert.messageText = "NDJSON 格式化失败"
                    alert.informativeText = error.localizedDescription + "。请在左侧修正后重试。原文件未修改。"
                    if let window = self.window { alert.beginSheetModal(for: window) }
                }
            }
        }
    }
    private var firstRow: Int { mode != .ndjson && headerToggle.state == .on && !(index?.ranges.isEmpty ?? true) ? 1 : 0 }
    private func sourceRow(_ row: Int) -> Int { displayedRows?[row] ?? row + firstRow }
    private func cells(_ row: Int) -> [String] {
        if let cells = rowCache[row] { return cells }
        guard let index, !pendingRows.contains(row) else { return [] }
        pendingRows.insert(row)
        let job = token, revision = columnRevision, offset = columnOffset
        queue.async { [weak self] in
            guard !job.cancelled else { return }
            let values = index.cells(at: row, byteLimit: 1200, columns: offset..<offset + 100)
            DispatchQueue.main.async { [weak self] in
                guard let self, !job.cancelled, revision == self.columnRevision else { return }
                if self.rowCache.count >= 256 { self.rowCache.removeAll() }
                self.rowCache[row] = values; self.pendingRows.remove(row)
                let visible = self.table.rows(in: self.table.visibleRect)
                if visible.location != NSNotFound {
                    for visibleRow in visible.location..<min(NSMaxRange(visible), self.numberOfRows(in: self.table)) where self.sourceRow(visibleRow) == row {
                        self.table.reloadData(forRowIndexes: IndexSet(integer: visibleRow), columnIndexes: IndexSet(integersIn: 0..<self.table.numberOfColumns))
                    }
                }
            }
        }
        return []
    }
    private func configureColumns() {
        columnRevision += 1; rowCache.removeAll(); pendingRows.removeAll()
        if firstRow == 1, let index {
            let job = token, revision = columnRevision, offset = columnOffset
            queue.async { [weak self] in
                guard !job.cancelled else { return }
                let names = index.cells(at: 0, byteLimit: 400, columns: offset..<offset + 100)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled, revision == self.columnRevision else { return }
                    for column in self.table.tableColumns {
                        if let i = Int(column.identifier.rawValue), names.indices.contains(i - offset), !names[i - offset].isEmpty { column.title = names[i - offset] }
                    }
                }
            }
        }
        for c in table.tableColumns { table.removeTableColumn(c) }
        let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row")); number.title = "记录"; number.width = 65; table.addTableColumn(number)
        if mode == .ndjson {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("json")); c.title = "NDJSON · 选择记录展开"; c.width = 360; c.minWidth = 80; c.resizingMask = .autoresizingMask; table.addTableColumn(c)
        } else if let index {
            for i in columnOffset..<min(columnOffset + pageSize, index.columnCount) {
                let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i)))
                c.title = "列 \(i + 1)"
                c.width = 160; c.minWidth = 45; table.addTableColumn(c)
            }
        }
        previous.isEnabled = columnOffset > 0; next.isEnabled = columnOffset + pageSize < (index?.columnCount ?? 0)
        table.reloadData()
    }
    private func updateStatus() {
        guard let index else { return }
        let total = max(0, index.ranges.count - firstRow), shown = displayedRows?.count ?? total
        status.stringValue = mode == .ndjson ? "\(shown) / \(total) 条 · 逐条解析 · 编辑后自动更新" : "\(shown) / \(total) 条 · \(index.columnCount) 列 · 当前列 \(columnOffset + 1)–\(min(columnOffset + pageSize, index.columnCount)) · 编辑后自动更新"
    }
    @objc private func changeHeader() { filterRows(); configureColumns() }
    @objc private func previousColumns() { columnOffset = max(0, columnOffset - pageSize); selectedColumn = columnOffset; configureColumns(); updateStatus() }
    @objc private func nextColumns() { columnOffset += pageSize; selectedColumn = columnOffset; configureColumns(); updateStatus() }
    @objc private func filterRows() {
        searchToken.cancel(); searchToken = JSONTaskToken(); let job = searchToken
        guard let index else { return }
        let query = search.stringValue, start = firstRow
        if query.isEmpty { displayedRows = nil; table.reloadData(); updateStatus(); return }
        status.stringValue = "正在后台筛选…"
        searchQueue.async { [weak self] in
            var matches: [Int] = []
            for row in start..<index.ranges.count {
                if job.cancelled { return }
                let match: Bool
                if index.mode == .ndjson { match = String(decoding: index.data[index.ranges[row]], as: UTF8.self).localizedCaseInsensitiveContains(query) }
                else { match = index.cells(at: row).contains { $0.localizedCaseInsensitiveContains(query) } }
                if match { matches.append(row) }
            }
            DispatchQueue.main.async { [weak self] in guard let self, !job.cancelled else { return }; self.displayedRows = matches; self.table.reloadData(); self.updateStatus() }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { displayedRows?.count ?? max(0, (index?.ranges.count ?? 0) - firstRow) }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index, let column else { return nil }
        let cellID = NSUserInterfaceItemIdentifier("record.cell")
        let label = table.makeView(withIdentifier: cellID, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        label.identifier = cellID; label.font = .monospacedSystemFont(ofSize: 12, weight: .regular); label.lineBreakMode = .byTruncatingTail
        let source = sourceRow(row)
        if column.identifier.rawValue == "row" { label.stringValue = String(source + 1); label.textColor = .secondaryLabelColor }
        else if mode == .ndjson { label.stringValue = index.preview(at: source); label.textColor = .labelColor }
        else {
            let values = cells(source), col = (Int(column.identifier.rawValue) ?? 0) - columnOffset
            label.stringValue = col >= 0 && col < values.count ? String(values[col].prefix(300)).replacingOccurrences(of: "\n", with: " ↵ ").replacingOccurrences(of: "\r", with: "") : ""
            label.textColor = .labelColor
        }
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        showSelection()
        if !restoringSelection, !token.cancelled, let index, table.selectedRow >= 0, table.selectedRow < numberOfRows(in: table) {
            onReveal?(index.ranges[sourceRow(table.selectedRow)].lowerBound)
        }
    }
    @objc private func selectCell() {
        if table.clickedColumn >= 0, let column = Int(table.tableColumns[table.clickedColumn].identifier.rawValue) { selectedColumn = column }
        showSelection()
    }
    private func showSelection() {
        guard let index, table.selectedRow >= 0, table.selectedRow < numberOfRows(in: table) else {
            selectionRevision += 1; jsonDetail?.cancel(); jsonDetail?.removeFromSuperview(); jsonDetail = nil
            detail.string = "选择记录或单元格查看内容。"; return
        }
        guard !token.cancelled else { return }
        let row = sourceRow(table.selectedRow)
        if mode != .ndjson {
            selectionRevision += 1
            let revision = selectionRevision, column = selectedColumn, job = token
            detail.string = "正在读取单元格…"
            queue.async { [weak self] in
                guard !job.cancelled else { return }
                let value = index.cells(at: row, byteLimit: 1_048_576, columns: column..<column + 1).first ?? ""
                DispatchQueue.main.async { [weak self] in
                    guard let self, !job.cancelled, revision == self.selectionRevision else { return }
                    self.detail.string = value + (value.utf8.count > 1_048_576 ? "\n\n单元格过长，仅预览前 1 MiB，完整内容请查看左侧原文。" : "")
                }
            }
        } else {
            jsonDetail?.cancel(); jsonDetail?.removeFromSuperview()
            let panel = JSONInspectorView(frame: .zero); panel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(panel); jsonDetail = panel
            NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: detailScroll.leadingAnchor), panel.trailingAnchor.constraint(equalTo: detailScroll.trailingAnchor), panel.topAnchor.constraint(equalTo: detailScroll.topAnchor), panel.bottomAnchor.constraint(equalTo: detailScroll.bottomAnchor)])
            panel.onClose = { [weak self, weak panel] in panel?.removeFromSuperview(); self?.jsonDetail = nil }
            panel.onRefresh = { [weak self] in self?.showSelection() }
            panel.load(url: nil, text: nil, recordData: index.data, recordRange: index.ranges[row])
            panel.onFormatted = onFormatted
            let base = index.ranges[row].lowerBound
            panel.onReveal = { [weak self] offset in self?.onReveal?(base + offset) }
        }
    }
    var onFormatted: ((URL) -> Void)?
}

import AppKit

final class FolderSearchWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let folder = NSTextField(labelWithString: "请选择目录")
    private let query = NSTextField(), replacement = NSTextField(), extensions = NSTextField()
    private let regex = NSButton(checkboxWithTitle: "正则表达式", target: nil, action: nil)
    private let sensitive = NSButton(checkboxWithTitle: "区分大小写", target: nil, action: nil)
    private let table = NSTableView(), status = NSTextField(wrappingLabelWithString: "递归搜索目录，跳过隐藏文件、应用包和符号链接。单文件最多 32 MiB；预览最多 5000 项。")
    private let search = NSButton(title: "搜索 / 预览替换", target: nil, action: nil)
    private let apply = NSButton(title: "替换勾选项…", target: nil, action: nil)
    private var root: URL?, result: FolderSearchResult?, options: FolderSearchOptions?
    private var token = JSONTaskToken()
    private let queue = DispatchQueue(label: "textstack.folder-search", qos: .userInitiated)
    var onReveal: ((URL, Int) -> Void)?
    var openPaths: (() -> Set<String>)?
    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: win); win.title = "目录搜索与替换"; win.delegate = self; win.minSize = NSSize(width: 850, height: 500); setup(); win.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { token.cancel() }
    private func setup() {
        status.maximumNumberOfLines = 4
        let choose = NSButton(title: "选择目录…", target: self, action: #selector(chooseFolder))
        let cancel = NSButton(title: "取消搜索", target: self, action: #selector(invalidate))
        let all = NSButton(title: "全选", target: self, action: #selector(selectAllHits))
        let none = NSButton(title: "清空勾选", target: self, action: #selector(selectNone))
        search.target = self; search.action = #selector(run); apply.target = self; apply.action = #selector(replaceSelected); apply.isEnabled = false
        query.placeholderString = "搜索内容"; replacement.placeholderString = "替换文本（正则支持 $1 等捕获组）"; extensions.placeholderString = "扩展名，例如 log,txt,json；留空为全部"
        for field in [query, replacement, extensions] { field.delegate = self }
        for button in [regex, sensitive] { button.target = self; button.action = #selector(invalidate) }
        for (id, title, width) in [("checked", "替换", 45.0), ("file", "文件 / 行", 340.0), ("before", "匹配内容", 240.0), ("after", "替换为", 240.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
            if id == "checked" { let cell = NSButtonCell(); cell.setButtonType(.switch); cell.title = ""; column.dataCell = cell; column.isEditable = true }
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 27; table.target = self; table.doubleAction = #selector(reveal)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let top = NSStackView(views: [choose, folder]); top.spacing = 10
        let controls = NSStackView(views: [regex, sensitive, search, cancel, all, none, apply]); controls.spacing = 10
        let stack = NSStackView(views: [top, query, replacement, extensions, controls, status, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        guard let content = window?.contentView else { return }; content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16)])
        for view in [top, query, replacement, extensions, controls, status, scroll] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    func controlTextDidChange(_ obj: Notification) { invalidate() }
    @objc private func invalidate() { token.cancel(); result = nil; options = nil; table.reloadData(); apply.isEnabled = false; search.isEnabled = true; status.stringValue = "条件已修改或搜索已取消，请重新搜索。" }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }; self.invalidate(); self.root = url; self.folder.stringValue = url.path
        }
    }
    @objc private func run() {
        guard let root else { status.stringValue = "请先选择目录"; return }
        invalidate(); token = JSONTaskToken(); let job = token
        let options = FolderSearchOptions(query: query.stringValue, replacement: replacement.stringValue, regex: regex.state == .on, caseSensitive: sensitive.state == .on, extensions: extensions.stringValue)
        search.isEnabled = false; status.stringValue = "正在搜索…"
        queue.async { [weak self] in
            do {
                let found = try FolderSearch.scan(root: root, options: options, cancelled: { job.cancelled })
                DispatchQueue.main.async {
                    guard let self, !job.cancelled else { return }; self.result = found; self.options = options; self.table.reloadData(); self.search.isEnabled = true; self.apply.isEnabled = !found.hits.isEmpty
                    self.status.stringValue = "\(found.files.count) 个文件 · \(found.hits.count) 处匹配" + (found.limited ? " · 已达到预览 / 内存上限，请缩小搜索范围" : "") + (found.skipped.isEmpty ? "" : "\n跳过：" + found.skipped.prefix(8).joined(separator: "；")) + "\n双击结果打开原文；替换前会备份。已打开文件请使用编辑器搜索栏的替换预览。"
                }
            } catch { DispatchQueue.main.async { guard let self, !job.cancelled else { return }; self.search.isEnabled = true; self.status.stringValue = error.localizedDescription } }
        }
    }
    @objc private func selectAllHits() { if let count = result?.hits.count { for i in 0..<count { result?.hits[i].selected = true } }; table.reloadData() }
    @objc private func selectNone() { if let count = result?.hits.count { for i in 0..<count { result?.hits[i].selected = false } }; table.reloadData() }
    @objc private func reveal() { guard let result, result.hits.indices.contains(table.clickedRow) else { return }; let hit = result.hits[table.clickedRow]; onReveal?(result.files[hit.file].url, hit.line) }
    @objc private func replaceSelected() {
        guard let result, let options else { return }
        let count = result.hits.filter(\.selected).count
        guard count > 0 else { status.stringValue = "请勾选需要替换的匹配项"; return }
        let alert = NSAlert(); alert.messageText = "替换 \(count) 处勾选的匹配？"; alert.informativeText = "修改磁盘上的文件，并保存原文件备份。该操作不进入编辑器撤销历史。"; alert.addButton(withTitle: "备份并替换"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let blocked = self.openPaths?() ?? []
            let backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TextStack/ReplacementBackups/" + UUID().uuidString)
            self.apply.isEnabled = false; self.search.isEnabled = false
            self.queue.async {
                do {
                    let changed = try FolderSearch.replace(result: result, options: options, backup: backup, blockedPaths: blocked)
                    DispatchQueue.main.async { self.invalidate(); self.status.stringValue = "已替换 \(changed.count) 个文件。备份：\(backup.path)" }
                } catch { DispatchQueue.main.async { self.invalidate(); self.status.stringValue = error.localizedDescription } }
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { result?.hits.count ?? 0 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let result, result.hits.indices.contains(row) else { return nil }; let hit = result.hits[row]
        switch tableColumn?.identifier.rawValue {
        case "checked": return hit.selected ? 1 : 0
        case "file": return result.files[hit.file].url.path.replacingOccurrences(of: (root?.path ?? "") + "/", with: "") + ":\(hit.line)"
        case "before": return hit.before.replacingOccurrences(of: "\n", with: " ↵ ")
        default: return hit.after.replacingOccurrences(of: "\n", with: " ↵ ")
        }
    }
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool { tableColumn?.identifier.rawValue == "checked" }
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) { guard tableColumn?.identifier.rawValue == "checked", result?.hits.indices.contains(row) == true else { return }; result?.hits[row].selected = (object as? NSNumber)?.boolValue ?? false }
}

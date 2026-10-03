import AppKit

final class LogAnalysisWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let loader: () throws -> Data
    private let field = NSTextField(), value = NSTextField(), start = NSTextField(), end = NSTextField(), offset = NSTextField(), year = NSTextField()
    private let grain = NSPopUpButton(), format = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "设置条件后分析。字段值精确匹配，留空不过滤；无时间戳堆栈续行跟随前一条记录。")
    private let analyze = NSButton(title: "分析 / 筛选", target: nil, action: nil)
    private let export = NSButton(title: "导出完整筛选日志…", target: nil, action: nil)
    private let timeline = NSTableView(), matches = NSTableView()
    private var result: LogAnalysisResult?, cached: Data?
    private var token = JSONTaskToken()
    private let queue = DispatchQueue(label: "textstack.log-analysis", qos: .userInitiated)
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("textstack-log-" + UUID().uuidString)
    private var jobOffset = 0
    private var maxBucketCount = 1
    var sourceURL: URL?
    var onReveal: ((Int) -> Void)?
    var onExported: ((URL) -> Void)?
    init(title: String, loader: @escaping () throws -> Data) {
        self.loader = loader
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 750), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: win); win.title = "日志时间轴与字段筛选 — " + title; win.minSize = NSSize(width: 900, height: 600); win.delegate = self; setup(); win.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { token.cancel(); try? FileManager.default.removeItem(at: folder) }
    func windowWillClose(_ notification: Notification) { token.cancel() }
    private func setup() {
        status.maximumNumberOfLines = 4
        field.stringValue = "level"; value.placeholderString = "例如 ERROR；留空不过滤"
        start.placeholderString = "开始时间（含边界，留空不限）"; end.placeholderString = "结束时间（含边界，留空不限）"
        grain.addItems(withTitles: ["每分钟", "每小时", "每天"])
        format.addItems(withTitles: ["自动检测时间", "ISO", "Syslog", "Apache", "Unix 秒", "Unix 毫秒"])
        let seconds = TimeZone.current.secondsFromGMT(); offset.stringValue = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        year.stringValue = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
        for control in [field, value, start, end, offset, year] { control.delegate = self }
        for popup in [grain, format] { popup.target = self; popup.action = #selector(invalidate) }
        analyze.target = self; analyze.action = #selector(run); export.target = self; export.action = #selector(exportLog); export.isEnabled = false
        let cancel = NSButton(title: "取消", target: self, action: #selector(invalidate))
        let rules = NSStackView(views: [NSTextField(labelWithString: "字段"), field, NSTextField(labelWithString: "等于"), value, grain, analyze, cancel, export]); rules.spacing = 8
        field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let time = NSStackView(views: [start, end, format, NSTextField(labelWithString: "时区"), offset, NSTextField(labelWithString: "无年份使用"), year]); time.spacing = 8
        start.widthAnchor.constraint(equalTo: end.widthAnchor).isActive = true
        offset.widthAnchor.constraint(equalToConstant: 70).isActive = true; year.widthAnchor.constraint(equalToConstant: 65).isActive = true
        setupTable(timeline, columns: [("time", "时间 / 分布", 410), ("count", "记录数", 100), ("error", "ERROR / FATAL", 140), ("warn", "WARN", 100), ("line", "首条源行", 100)])
        setupTable(matches, columns: [("line", "源行", 90), ("text", "筛选结果（最多显示 1000 行）", 850)])
        timeline.target = self; timeline.doubleAction = #selector(revealTime); matches.target = self; matches.doubleAction = #selector(revealMatch)
        let hint = NSTextField(wrappingLabelWithString: "首次分析读取打开工具时的内容；后续复用快照。双击时间桶或筛选行定位原文。支持 JSON 日志、key=value 字段、常见级别及方括号线程。")
        let stack = NSStackView(views: [rules, time, hint, status, scroll(timeline), scroll(matches)]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        guard let content = window?.contentView else { return }; content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16)])
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.arrangedSubviews[4].heightAnchor.constraint(equalTo: stack.arrangedSubviews[5].heightAnchor).isActive = true
    }
    private func scroll(_ table: NSTableView) -> NSScrollView { let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; return scroll }
    private func setupTable(_ table: NSTableView, columns: [(String, String, Double)]) {
        for (id, title, width) in columns { let col = NSTableColumn(identifier: .init(id)); col.title = title; col.width = width; table.addTableColumn(col) }
        table.delegate = self; table.dataSource = self; table.rowHeight = 26
    }
    func controlTextDidChange(_ obj: Notification) { invalidate() }
    @objc private func invalidate() { token.cancel(); result = nil; export.isEnabled = false; analyze.isEnabled = true; timeline.reloadData(); matches.reloadData(); status.stringValue = "条件已修改 / 已取消，请重新分析。" }
    @objc private func run() {
        invalidate(); token = JSONTaskToken(); let job = token
        do {
            let zone = try TimeRangeOptions.parseOffset(offset.stringValue)
            guard let assumedYear = Int(year.stringValue), (1...9999).contains(assumedYear) else { throw ProcessingError(message: "年份必须为 1–9999") }
            let options = LogAnalysisOptions(bucketSeconds: [60, 3600, 86400][grain.indexOfSelectedItem], offset: zone, year: assumedYear, format: format.indexOfSelectedItem == 0 ? nil : TimestampFormat.allCases[format.indexOfSelectedItem - 1], field: field.stringValue, value: value.stringValue, start: try TimeRangeOptions.parseBoundary(start.stringValue, offset: zone), end: try TimeRangeOptions.parseBoundary(end.stringValue, offset: zone))
            let cached = self.cached, loader = self.loader, output = folder.appendingPathComponent(UUID().uuidString + ".log"), folder = self.folder
            analyze.isEnabled = false; status.stringValue = "正在后台分析…"
            queue.async { [weak self] in
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let data = try cached ?? loader()
                    let result = try LogAnalysis.run(data: data, options: options, output: output, cancelled: { job.cancelled })
                    DispatchQueue.main.async {
                        guard let self, !job.cancelled else { try? FileManager.default.removeItem(at: output); return }
                        self.cached = data; self.result = result; self.jobOffset = zone; self.maxBucketCount = result.buckets.map(\.count).max() ?? 1; self.timeline.reloadData(); self.matches.reloadData(); self.export.isEnabled = true; self.analyze.isEnabled = true
                        self.status.stringValue = "\(result.total) 行 · \(result.dated) 行含时间戳 · 筛选 \(result.matched) 行\n级别：" + result.levels.keys.sorted().map { "\($0) \(result.levels[$0]!)" }.joined(separator: " · ") + "\n识别字段：" + result.fields.keys.sorted().prefix(32).joined(separator: ", ") + (result.fields.count > 32 ? "（另有 \(result.fields.count - 32) 个字段）" : "") + (result.dated == 0 ? "\n未识别时间戳，可手动选格式；字段筛选仍可使用。" : "")
                    }
                } catch { DispatchQueue.main.async { guard let self, !job.cancelled else { return }; self.analyze.isEnabled = true; self.status.stringValue = error.localizedDescription } }
            }
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func revealTime() { guard let result, result.buckets.indices.contains(timeline.clickedRow) else { return }; onReveal?(result.buckets[timeline.clickedRow].firstLine) }
    @objc private func revealMatch() { guard let result, result.samples.indices.contains(matches.clickedRow) else { return }; onReveal?(result.samples[matches.clickedRow].0) }
    @objc private func exportLog() {
        guard let output = result?.output else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "filtered.log"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            // Copy the bounded-memory full result in the worker queue, preserving the selected result URL.
            if destination.resolvingSymlinksInPath() == self.sourceURL?.resolvingSymlinksInPath() { self.status.stringValue = "导出不能覆盖源日志，请另选文件名。"; return }
            self.export.isEnabled = false
            self.queue.async {
                let staging = destination.deletingLastPathComponent().appendingPathComponent(".textstack-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staging) }
                do {
                    try FileManager.default.copyItem(at: output.url, to: staging)
                    if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) } else { try FileManager.default.moveItem(at: staging, to: destination) }
                    DispatchQueue.main.async { self.export.isEnabled = self.result != nil; self.status.stringValue = "已导出：" + destination.path; self.onExported?(destination) }
                } catch { DispatchQueue.main.async { self.export.isEnabled = self.result != nil; self.status.stringValue = error.localizedDescription } }
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === timeline ? result?.buckets.count ?? 0 : result?.samples.count ?? 0 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let result else { return nil }
        if tableView === matches { return tableColumn?.identifier.rawValue == "line" ? String(result.samples[row].0) : result.samples[row].1 }
        let bucket = result.buckets[row]
        switch tableColumn?.identifier.rawValue {
        case "count": return bucket.count
        case "error": return bucket.errors
        case "warn": return bucket.warnings
        case "line": return bucket.firstLine
        default:
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.timeZone = TimeZone(secondsFromGMT: jobOffset)
            let maxCount = maxBucketCount
            return formatter.string(from: bucket.time) + "  " + String(repeating: "▇", count: max(1, Int(Double(bucket.count) / Double(maxCount) * 22)))
        }
    }
}

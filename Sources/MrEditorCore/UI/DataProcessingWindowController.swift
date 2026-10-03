import AppKit

/// A source snapshot, editable rules, bounded preview and explicit full-result export.
final class DataProcessingWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    enum Kind { case timeRange, csv }
    private let kind: Kind
    private let loadData: (() throws -> Data)
    private let sourceURL: URL?
    private let folder: URL
    private let queue = DispatchQueue(label: "mreditor.data-processing", qos: .userInitiated)
    private var token = JSONTaskToken()
    private var source: Data?
    private var result: ProcessingResult?
    private let start = NSTextField(), end = NSTextField(), offset = NSTextField(), year = NSTextField()
    private let format = NSPopUpButton(), delimiter = NSPopUpButton(), empty = NSPopUpButton(), conversion = NSPopUpButton()
    private let columns = NSTextField(), fill = NSTextField()
    private let continuation = NSButton(checkboxWithTitle: "保留匹配日志的无时间戳续行（如堆栈）", target: nil, action: nil)
    private let header = NSButton(checkboxWithTitle: "首条记录作为表头（不参与清洗）", target: nil, action: nil)
    private let trim = NSButton(checkboxWithTitle: "去除所选列首尾空白", target: nil, action: nil)
    private let dedup = NSButton(checkboxWithTitle: "按所选列去重，保留第一条（留空按整条记录）", target: nil, action: nil)
    private let preview = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "设置规则后点击预览。结果采用 UTF-8，源文件不变。")
    private let generate = NSButton(title: "预览结果", target: nil, action: nil)
    private let export = NSButton(title: "导出完整结果…", target: nil, action: nil)
    private let cancel = NSButton(title: "取消处理", target: nil, action: nil)
    var onExported: ((URL) -> Void)?

    init(kind: Kind, sourceURL: URL?, loadData: @escaping () throws -> Data) {
        self.kind = kind; self.sourceURL = sourceURL; self.loadData = loadData
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mreditor-processing-" + UUID().uuidString)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 690), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = (kind == .timeRange ? "时间范围筛选" : "CSV / TSV 数据清洗") + " — " + (sourceURL?.lastPathComponent ?? "未保存文档")
        window.minSize = NSSize(width: 760, height: 650); window.delegate = self
        setup(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { token.cancel(); try? FileManager.default.removeItem(at: folder) }
    func windowWillClose(_ notification: Notification) { token.cancel(); try? FileManager.default.removeItem(at: folder) }

    private func row(_ title: String, _ views: [NSView]) -> NSStackView {
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 125).isActive = true
        let row = NSStackView(views: [label] + views); row.spacing = 8; row.alignment = .centerY
        for view in views { view.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        return row
    }
    private func setup() {
        guard let content = window?.contentView else { return }
        let rules = NSStackView(); rules.orientation = .vertical; rules.alignment = .leading; rules.spacing = 8
        let hint = NSTextField(wrappingLabelWithString: "首次预览读取源文件，包含打开工具时的未保存修改；后续预览复用已读取的内容。源文档变化后请重新打开工具。")
        hint.textColor = .secondaryLabelColor; rules.addArrangedSubview(hint)
        if kind == .timeRange {
            start.placeholderString = "2026-10-02 10:00:00.000"; end.placeholderString = "留空表示不限制"
            let seconds = TimeZone.current.secondsFromGMT()
            offset.stringValue = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
            year.stringValue = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
            format.addItems(withTitles: ["自动检测", "ISO 日期时间", "Syslog（无年份）", "Apache / nginx", "Unix 秒", "Unix 毫秒"])
            continuation.state = .on
            rules.addArrangedSubview(row("开始（含边界）", [start])); rules.addArrangedSubview(row("结束（含边界）", [end]))
            rules.addArrangedSubview(row("日志时间格式", [format])); rules.addArrangedSubview(row("无时区时间使用", [offset]))
            rules.addArrangedSubview(row("Syslog 起始年份", [year]))
            rules.addArrangedSubview(continuation)
            rules.addArrangedSubview(NSTextField(labelWithString: "支持 yyyy-MM-dd HH:mm:ss[.SSS] 或 ISO 时间；日志自带时区优先，无时间戳开头行不保留。"))
        } else {
            delimiter.addItems(withTitles: ["CSV（逗号）", "TSV（制表符）"])
            if sourceURL?.pathExtension.lowercased() == "tsv" { delimiter.selectItem(at: 1) }
            columns.placeholderString = "留空表示所有列；例如 1,3（从 1 开始）"
            empty.addItems(withTitles: ["保留空值", "填充指定值", "删除含空值的记录"])
            conversion.addItems(withTitles: ["保留文本", "整数（64 位）", "十进制数", "布尔值（true / false）"])
            fill.placeholderString = "空值替换文本"
            header.state = .on; trim.state = .on
            rules.addArrangedSubview(row("文件分隔符", [delimiter])); rules.addArrangedSubview(header)
            rules.addArrangedSubview(row("清洗 / 去重列", [columns])); rules.addArrangedSubview(trim); rules.addArrangedSubview(dedup)
            rules.addArrangedSubview(row("空值处理", [empty, fill])); rules.addArrangedSubview(row("所选列类型转换", [conversion]))
            rules.addArrangedSubview(NSTextField(labelWithString: "顺序：去空白 → 空值处理 → 类型转换 → 去重。转换失败会提示记录和列，不生成部分结果。"))
        }
        for field in [start, end, offset, year, columns, fill] { field.delegate = self }
        for button in [continuation, header, trim, dedup] { button.target = self; button.action = #selector(rulesChanged) }
        for popup in [format, delimiter, empty, conversion] { popup.target = self; popup.action = #selector(rulesChanged) }
        generate.target = self; generate.action = #selector(run)
        export.target = self; export.action = #selector(exportResult); export.isEnabled = false
        cancel.target = self; cancel.action = #selector(cancelRun); cancel.isEnabled = false
        let buttons = NSStackView(views: [generate, cancel, export]); buttons.spacing = 12
        preview.isEditable = false; preview.isRichText = false; preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        preview.textContainerInset = NSSize(width: 10, height: 10)
        let scroll = NSScrollView(); scroll.documentView = preview; scroll.hasVerticalScroller = true
        for view in [rules, buttons, status, scroll] { content.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            rules.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), rules.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), rules.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: rules.bottomAnchor, constant: 12), buttons.leadingAnchor.constraint(equalTo: rules.leadingAnchor),
            status.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 10), status.leadingAnchor.constraint(equalTo: rules.leadingAnchor), status.trailingAnchor.constraint(equalTo: rules.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        for view in rules.arrangedSubviews { view.widthAnchor.constraint(equalTo: rules.widthAnchor).isActive = true }
    }
    func controlTextDidChange(_ obj: Notification) { rulesChanged() }
    @objc private func rulesChanged() {
        token.cancel(); if let result { try? FileManager.default.removeItem(at: result.url) }; result = nil; export.isEnabled = false; cancel.isEnabled = false; generate.isEnabled = true
        preview.string = ""; status.stringValue = "规则已修改，请重新预览。"
    }
    @objc private func cancelRun() { rulesChanged(); status.stringValue = "已取消处理。" }

    @objc private func run() {
        token.cancel(); token = JSONTaskToken(); let job = token
        if let result { try? FileManager.default.removeItem(at: result.url) }
        result = nil; export.isEnabled = false
        do {
            let operation: (Data, URL, () -> Bool) throws -> ProcessingResult
            let ext: String
            if kind == .timeRange {
                let seconds = try TimeRangeOptions.parseOffset(offset.stringValue)
                guard let assumedYear = Int(year.stringValue), (1...9999).contains(assumedYear) else { throw ProcessingError(message: "假定年份必须为 1–9999") }
                let options = TimeRangeOptions(start: try TimeRangeOptions.parseBoundary(start.stringValue, offset: seconds), end: try TimeRangeOptions.parseBoundary(end.stringValue, offset: seconds), format: format.indexOfSelectedItem == 0 ? nil : TimestampFormat.allCases[format.indexOfSelectedItem - 1], offset: seconds, year: assumedYear, keepContinuation: continuation.state == .on)
                operation = { try TimeRangeProcessor.run(data: $0, options: options, output: $1, cancelled: $2) }; ext = "log"
            } else {
                let options = CSVCleaningOptions(mode: delimiter.indexOfSelectedItem == 1 ? .tsv : .csv, header: header.state == .on, columns: try CSVCleaningOptions.parseColumns(columns.stringValue), trim: trim.state == .on, deduplicate: dedup.state == .on, emptyAction: CSVCleaningOptions.EmptyAction(rawValue: empty.indexOfSelectedItem)!, fillValue: fill.stringValue, conversion: CSVCleaningOptions.Conversion(rawValue: conversion.indexOfSelectedItem)!)
                operation = { try CSVCleaningProcessor.run(data: $0, options: options, output: $1, cancelled: $2) }; ext = options.mode == .tsv ? "tsv" : "csv"
            }
            generate.isEnabled = false; cancel.isEnabled = true; preview.string = ""; status.stringValue = "正在后台处理…可取消"
            let folder = self.folder, cached = source, loader = loadData
            let output = folder.appendingPathComponent(UUID().uuidString + "." + ext)
            queue.async { [weak self] in
                do {
                    if job.cancelled { throw CancellationError() }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let data = try cached ?? loader()
                    let result = try operation(data, output, { job.cancelled })
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !job.cancelled else { try? FileManager.default.removeItem(at: output); return }
                        self.source = data; self.result = result; self.preview.string = result.preview
                        self.status.stringValue = result.summary; self.generate.isEnabled = true; self.cancel.isEnabled = false; self.export.isEnabled = true
                    }
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !job.cancelled else { return }
                        self.status.stringValue = error.localizedDescription; self.generate.isEnabled = true; self.cancel.isEnabled = false
                    }
                }
            }
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func exportResult() {
        guard let result, let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (sourceURL?.deletingPathExtension().lastPathComponent ?? "result") + (kind == .timeRange ? ".filtered." : ".cleaned.") + result.url.pathExtension
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            if let sourceURL = self.sourceURL, destination.resolvingSymlinksInPath().standardizedFileURL == sourceURL.resolvingSymlinksInPath().standardizedFileURL {
                self.status.stringValue = "请另选文件名，清洗 / 筛选结果不能覆盖源文件。"; return
            }
            do {
                // Open before dispatch so later rule edits cannot remove the source before copying begins.
                let input = try FileHandle(forReadingFrom: result.url)
                self.token.cancel(); self.token = JSONTaskToken(); let job = self.token
                self.generate.isEnabled = false; self.export.isEnabled = false; self.cancel.isEnabled = true
                self.status.stringValue = "正在导出完整结果…可取消"
                self.queue.async { [weak self] in
                    let staging = destination.deletingLastPathComponent().appendingPathComponent(".mreditor-" + UUID().uuidString)
                    defer { try? input.close(); try? FileManager.default.removeItem(at: staging) }
                    do {
                        guard FileManager.default.createFile(atPath: staging.path, contents: nil) else { throw ProcessingError(message: "无法创建导出文件") }
                        let output = try FileHandle(forWritingTo: staging); defer { try? output.close() }
                        while true {
                            if job.cancelled { throw CancellationError() }
                            guard let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
                            try output.write(contentsOf: chunk)
                        }
                        try output.synchronize(); try output.close()
                        if job.cancelled { throw CancellationError() }
                        if FileManager.default.fileExists(atPath: destination.path) {
                            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                        } else { try FileManager.default.moveItem(at: staging, to: destination) }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !job.cancelled else { return }
                            self.status.stringValue = "已导出：" + destination.path
                            self.generate.isEnabled = true; self.export.isEnabled = true; self.cancel.isEnabled = false
                            self.onExported?(destination)
                        }
                    } catch {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !job.cancelled else { return }
                            self.status.stringValue = "导出失败：" + error.localizedDescription
                            self.generate.isEnabled = true; self.export.isEnabled = true; self.cancel.isEnabled = false
                        }
                    }
                }
            } catch { self.status.stringValue = "导出失败：" + error.localizedDescription }
        }
    }
}

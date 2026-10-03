import AppKit

final class CharacterInspectorWindowController: NSWindowController {
    private let loader: () throws -> String
    private let encoding = NSPopUpButton(), text = NSTextView()
    private let runButton = NSButton(title: "检查", target: nil, action: nil)
    private var cached: String?
    private var revision = 0
    init(loader: @escaping () throws -> String) {
        self.loader = loader
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: win); win.title = "字符与编码检查器"; setup(); win.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func setup() {
        encoding.addItems(withTitles: DetectedEncoding.selectable.map(\.displayName)); encoding.target = self; encoding.action = #selector(run)
        runButton.target = self; runButton.action = #selector(run)
        let row = NSStackView(views: [NSTextField(labelWithString: "检查目标编码"), encoding, runButton]); row.spacing = 10
        text.isEditable = false; text.isRichText = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.textContainerInset = NSSize(width: 10, height: 10)
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true
        let stack = NSStackView(views: [row, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        guard let content = window?.contentView else { return }; content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        run()
    }
    @objc private func run() {
        revision += 1; let current = revision, encoding = DetectedEncoding.selectable[encoding.indexOfSelectedItem], cached = self.cached, loader = self.loader
        text.string = "正在检查全文…（最多 64 MiB，内容快照）"; runButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let source = try cached ?? loader()
                guard source.utf8.count <= 64 * 1024 * 1024 else { throw ProcessingError(message: "文件超过 64 MiB，请选择需要检查的文本后重新打开检查器") }
                let report = CharacterInspection.report(source, target: encoding.stringEncoding, targetName: encoding.displayName)
                DispatchQueue.main.async { guard let self, self.revision == current else { return }; self.cached = source; self.text.string = report; self.runButton.isEnabled = true }
            } catch { DispatchQueue.main.async { guard let self, self.revision == current else { return }; self.text.string = error.localizedDescription; self.runButton.isEnabled = true } }
        }
    }
}

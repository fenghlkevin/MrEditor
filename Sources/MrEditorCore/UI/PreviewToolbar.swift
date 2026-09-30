import AppKit

/// Shared row above both panes. Additional actions belong in the leading stack;
/// the close control stays anchored to the trailing edge.
final class PreviewToolbar: NSView, NSSearchFieldDelegate {
    let search = NSSearchField()
    private let count = NSTextField(labelWithString: "")
    private var source: NSButton!
    private var contents: NSButton!
    var onAction: ((String, String) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        search.placeholderString = "搜索预览文档"
        search.setAccessibilityLabel("搜索预览文档")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        let previous = button("chevron.up", "上一处（Shift+Enter）", "previous")
        let next = button("chevron.down", "下一处（Enter）", "next")
        source = button("chevron.left.forwardslash.chevron.right", "切换源码", "source")
        contents = button("list.bullet", "目录", "contents")
        let stack = NSStackView(views: [search, count, previous, next, source, contents])
        stack.orientation = .horizontal
        stack.spacing = 8
        let close = button("xmark", L("markdown.closePreview"), "close")
        let line = NSBox(); line.boxType = .separator
        for view in [stack, close, line] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        let preferred = search.widthAnchor.constraint(equalToConstant: 280); preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -12),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), preferred,
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    private func button(_ symbol: String, _ label: String, _ action: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: #selector(performAction(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(action)
        button.toolTip = label
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
    @objc private func performAction(_ sender: NSButton) {
        guard let action = sender.identifier?.rawValue else { return }
        if action == "close" { onClose?() } else { onAction?(action, "") }
    }
    func controlTextDidChange(_ notification: Notification) { onAction?("search", search.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        if command == #selector(NSResponder.insertNewline(_:)) {
            onAction?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? "previous" : "next", ""); return true
        }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            search.stringValue = ""; onAction?("search", ""); window?.makeFirstResponder(nil); return true
        }
        return false
    }
    func update(_ state: [String: Any]) {
        if let value = state["count"] as? String { count.stringValue = value }
        if let value = state["source"] as? Bool { source.contentTintColor = value ? .controlAccentColor : .labelColor }
        if let value = state["available"] as? Bool { contents.isEnabled = value }
        if let value = state["expanded"] as? Bool { contents.contentTintColor = value ? .controlAccentColor : .labelColor }
    }
}

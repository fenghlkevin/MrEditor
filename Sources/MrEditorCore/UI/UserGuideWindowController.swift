import AppKit
import WebKit

/// Offline documentation; bundled images require no network access.
final class UserGuideWindowController: NSWindowController, WKNavigationDelegate, NSSearchFieldDelegate {
    private let webView = WKWebView()
    private let search = NSSearchField()
    private let result = NSTextField(labelWithString: "")
    static var guideURL: URL? { Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "UserGuide") }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TextStack · 功能使用说明"
        window.minSize = NSSize(width: 700, height: 500)
        super.init(window: window)
        window.center(); window.isReleasedWhenClosed = false
        search.placeholderString = "在手册中查找，按回车跳到下一处"
        search.delegate = self; search.target = self; search.action = #selector(findInGuide)
        search.sendsSearchStringImmediately = false
        result.font = .systemFont(ofSize: 12); result.textColor = .secondaryLabelColor
        let home = NSButton(title: "目录 / 快速开始", target: self, action: #selector(home))
        let toolbar = NSStackView(views: [home, search, result]); toolbar.spacing = 12
        let root = NSView(); window.contentView = root
        for view in [toolbar, webView] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor), webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        webView.navigationDelegate = self
        self.home()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func home() {
        guard let url = Self.guideURL else {
            webView.loadHTMLString("<h1>使用说明资源缺失</h1><p>请重新安装完整的 TextStack 安装包。</p>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        search.stringValue = ""; result.stringValue = ""
    }
    @objc private func findInGuide() {
        guard !search.stringValue.isEmpty else { result.stringValue = ""; return }
        let config = WKFindConfiguration(); config.wraps = true
        webView.find(search.stringValue, configuration: config) { [weak self] match in
            self?.result.stringValue = match.matchFound ? "已定位，可继续按回车" : "未找到"
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let root = Self.guideURL?.deletingLastPathComponent().standardizedFileURL.path,
              url.isFileURL, url.standardizedFileURL.path.hasPrefix(root + "/") else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}

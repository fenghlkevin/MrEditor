import AppKit
import WebKit
import UniformTypeIdentifiers

/// Offline preview. Document HTML cannot execute scripts or issue network requests.
final class MarkdownPreviewView: NSView, WKNavigationDelegate {
    private let scrollBridge = MarkdownScrollBridge()
    var onScroll: ((Double) -> Void)?
    private var loaded = false
    func scroll(to fraction: Double) {
        scrollFraction = max(0, min(1, fraction))
        guard loaded else { return }
        web.evaluateJavaScript("window.mdScrollTo(\(scrollFraction))", in: nil, in: .defaultClient, completionHandler: nil)
    }
    private let assets = MarkdownAssetHandler()
    private lazy var web: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        scrollBridge.onScroll = { [weak self] value in
            self?.scrollFraction = value
            self?.onScroll?(value)
        }
        configuration.userContentController.add(scrollBridge, contentWorld: .defaultClient, name: "markdownScroll")
        let script = """
        (() => {
            let applying = false, frame = 0;
            window.mdScrollTo = fraction => {
                applying = true;
                window.scrollTo(0, fraction * Math.max(0, document.documentElement.scrollHeight - innerHeight));
                requestAnimationFrame(() => requestAnimationFrame(() => { applying = false; }));
            };
            window.addEventListener('scroll', () => {
                if (applying || frame) return;
                frame = requestAnimationFrame(() => {
                    frame = 0;
                    if (!applying) window.webkit.messageHandlers.markdownScroll.postMessage(Math.max(0, Math.min(1, scrollY / Math.max(1, document.documentElement.scrollHeight - innerHeight))));
                });
            }, {passive:true});
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assets, forURLScheme: "mdasset")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        return web
    }()
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var lastText: String?
    private var lastURL: URL?
    private var lastDark = false
    private var scrollFraction = 0.0
    private let queue = DispatchQueue(label: "mreditor.markdown.preview", qos: .userInitiated)
    var onClose: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: L("markdown.preview")); title.font = .systemFont(ofSize: 12, weight: .medium); title.textColor = .secondaryLabelColor
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("markdown.closePreview"))!, target: self, action: #selector(closePreview)); close.isBordered = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [title, spacer, close]); header.spacing = 8
        for view in [header, web] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), header.heightAnchor.constraint(equalToConstant: 24),
            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func closePreview() { onClose?() }
    func update(source: String, url: URL?, dark: Bool) {
        guard source != lastText || url != lastURL || dark != lastDark else { return }
        lastText = source; lastURL = url; lastDark = dark
        revision += 1; let token = revision
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let html = MarkdownRenderer.page(body: MarkdownRenderer.render(source), dark: dark)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == token else { return }
                self.loaded = false
                self.assets.root = url?.deletingLastPathComponent()
                self.web.loadHTMLString(html, baseURL: URL(string: "mdasset://document/"))
            }
        }
        pending = item; queue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        scroll(to: scrollFraction)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated {
            if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else { decisionHandler(["about", "mdasset"].contains(action.request.url?.scheme ?? "") ? .allow : .cancel) }
    }
    func suspend() { loaded = false; revision += 1; pending?.cancel(); web.stopLoading(); lastText = nil }
    deinit { pending?.cancel() }
}

final class MarkdownAssetHandler: NSObject, WKURLSchemeHandler {
    var root: URL?
    static func imageURL(request: URL, root: URL) -> URL? {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let file = base.appendingPathComponent(request.path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/"), ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif"].contains(file.pathExtension.lowercased()) else { return nil }
        return file
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let request = task.request.url, let root, let file = Self.imageURL(request: request, root: root),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1024 * 1024,
              let data = try? Data(contentsOf: file) else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        task.didReceive(URLResponse(url: request, mimeType: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream", expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class MarkdownDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDragged(with event: NSEvent) { if let superview { onDrag?(superview.convert(event.locationInWindow, from: nil).x) } }
    override func mouseDown(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); NSRect(x: bounds.midX, y: 0, width: 1, height: bounds.height).fill() }
}

private final class MarkdownScrollBridge: NSObject, WKScriptMessageHandler {
    var onScroll: ((Double) -> Void)?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let fraction = message.body as? Double, fraction.isFinite else { return }
        onScroll?(max(0, min(1, fraction)))
    }
}

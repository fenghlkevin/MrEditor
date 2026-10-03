import AppKit
import WebKit
import UniformTypeIdentifiers

/// Bundled MrEditor document renderer. Document HTML is sanitized and CSP
/// prevents document scripts and network access; native images are directory-scoped.
final class MarkdownPreviewView: NSView, WKNavigationDelegate {
    private let scrollBridge = MarkdownScrollBridge()
    private let assets = MarkdownAssetHandler()
    private let renderer = MarkdownPreviewResources()
    private let rendererBridge = MarkdownRendererBridge()
    var onScroll: ((Double) -> Void)?
    var onClose: (() -> Void)?
    var onRendered: (() -> Void)?
    var usesSharedToolbar = false { didSet { closeButton.isHidden = usesSharedToolbar } }
    lazy var toolbar = PreviewToolbar()
    private lazy var closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("markdown.closePreview"))!, target: self, action: #selector(closePreview))

    func toolbarAction(_ action: String, value: String = "") {
        guard ready else { return }
        web.callAsyncJavaScript("""
        const field = document.querySelector('.preview-search input');
        if (action === 'search') { field.value = value; field.dispatchEvent(new Event('input')); }
        else if (action === 'previous' || action === 'next') {
            document.querySelectorAll('.preview-search > button')[action === 'previous' ? 0 : 1]?.click();
        } else document.querySelector(action === 'source' ? '.preview-source-toggle' : '.toc-toggle')?.click();
        """, arguments: ["action": action, "value": value], in: nil, in: .page, completionHandler: nil)
    }
    private var ready = false
    private var loading = false
    private var fallback = false
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var lastText: String?
    private var lastURL: URL?
    private var lastDark = false
    private var scrollFraction = 0.0
    private(set) var rendererError: String?

    // Internal read access also permits integration tests in the actual WebKit engine.
    private(set) lazy var web: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: "window.__mrRendererErrors = []; window.addEventListener('error', e => window.__mrRendererErrors.push(e.message || 'Resource failed: ' + (e.target?.src || e.target?.href || 'unknown')), true); window.addEventListener('securitypolicyviolation', e => window.__mrRendererErrors.push(e.violatedDirective + ': ' + e.blockedURI));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        rendererBridge.onReady = { [weak self] in
            guard let self, !self.fallback else { return }
            self.ready = true; self.loading = false; self.rendererError = nil
            if self.usesSharedToolbar { self.installSharedControls() }
            self.renderLatest()
        }
        configuration.userContentController.add(rendererBridge, name: "markdownRenderer")
        configuration.setURLSchemeHandler(assets, forURLScheme: "mdasset")
        configuration.setURLSchemeHandler(renderer, forURLScheme: MarkdownPreviewResources.scheme)
        scrollBridge.onScroll = { [weak self] value in
            guard let self, self.lastText != nil else { return }
            self.scrollFraction = value
            self.onScroll?(value)
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
        // This inset belongs only to the editor split pane; Quick Look has its
        // own native controls and uses the renderer's default toolbar spacing.
        let toolbarInset = """
        const inset = document.createElement('style');
        inset.textContent = '.preview-search { padding-right: 90px; } .toc-toggle { right: 48px; }';
        document.head.append(inset);
        """
        configuration.userContentController.addUserScript(WKUserScript(source: toolbarInset, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.allowsMagnification = true
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let close = closeButton
        toolbar.onAction = { [weak self] action, value in self?.toolbarAction(action, value: value) }
        toolbar.onClose = { [weak self] in self?.onClose?() }
        rendererBridge.onState = { [weak self] state in
            guard let self else { return }
            self.toolbar.update(state)
            if state["focus"] as? Bool == true { self.toolbar.window?.makeFirstResponder(self.toolbar.search) }
        }
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = L("markdown.closePreview")
        // Keep the document viewport flush with the source pane. The native close
        // button shares the renderer toolbar row and remains available in fallback.
        for view in [web, close] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: topAnchor), web.leadingAnchor.constraint(equalTo: leadingAnchor),
            web.trailingAnchor.constraint(equalTo: trailingAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 28), close.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func closePreview() { onClose?() }

    private func installSharedControls() {
        web.evaluateJavaScript("""
        const style = document.createElement('style');
        style.textContent = '.preview-search,.toc-toggle{display:none!important}.markdown-body{padding-top:8px!important}.toc-nav{top:8px!important}';
        document.head.append(style);
        const report = () => window.webkit.messageHandlers.markdownRenderer.postMessage({
            count: document.querySelector('.search-count')?.textContent || '',
            source: document.querySelector('.preview-source-toggle')?.getAttribute('aria-pressed') === 'true',
            available: !document.querySelector('#toc-container')?.hidden,
            expanded: document.querySelector('.toc-toggle')?.getAttribute('aria-expanded') === 'true'
        });
        new MutationObserver(report).observe(document.body, {subtree:true,childList:true,attributes:true,attributeFilter:['aria-pressed','aria-expanded','hidden']});
        document.addEventListener('keydown', e => {
            if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') {
                e.preventDefault(); e.stopImmediatePropagation();
                window.webkit.messageHandlers.markdownRenderer.postMessage({focus:true});
            }
        }, true);
        report();
        """, completionHandler: nil)
    }

    func scroll(to fraction: Double) {
        guard fraction.isFinite else { return }
        scrollFraction = max(0, min(1, fraction))
        guard ready || fallback else { return }
        web.callAsyncJavaScript("window.mdScrollTo(fraction)", arguments: ["fraction": scrollFraction], in: nil, in: .defaultClient, completionHandler: nil)
    }

    func update(source: String, url: URL?, dark: Bool) {
        guard source != lastText || url != lastURL || dark != lastDark else { return }
        if url != lastURL { scrollFraction = 0 }
        lastText = source; lastURL = url; lastDark = dark
        assets.root = url?.deletingLastPathComponent()
        revision += 1
        pending?.cancel()
        if !ready && !loading && !fallback {
            loadRenderer()
        } else {
            let item = DispatchWorkItem { [weak self] in self?.renderLatest() }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
    }

    private func loadRenderer() {
        guard renderer.rootDirectory != nil else { rendererError = "Renderer resource directory missing"; renderFallback(); return }
        ready = false; loading = true; fallback = false
        rendererError = nil
        web.load(URLRequest(url: MarkdownPreviewResources.indexURL))
    }

    private func renderLatest() {
        guard let source = lastText else { return }
        if fallback { renderFallback(); return }
        guard ready else { return }
        let token = revision
        let options: [String: Any] = ["dark": lastDark, "revision": token, "language": Locale.preferredLanguages.first ?? "en", "format": DocumentPreviewFormat.kind(for: lastURL) ?? "markdown", "syntax": DocumentPreviewFormat.language(for: lastURL)]
        web.callAsyncJavaScript("return await window.mrPreview.render(source, options)", arguments: ["source": source, "options": options], in: nil, in: .page) { [weak self] result in
            guard let self, self.revision == token, self.lastText != nil else { return }
            switch result {
            case .success:
                self.scroll(to: self.scrollFraction)
                self.onRendered?()
            case .failure(let error):
                self.rendererError = String(describing: error)
                NSLog("Markdown enhanced render failed: %@", String(describing: error))
                self.renderFallback()
            }
        }
    }

    private func renderFallback() {
        guard let source = lastText else { return }
        ready = false; loading = false; fallback = true
        let notice = "<p role=\"status\" style=\"color:#888;font-size:12px\">" + L("markdown.basicPreview") + "</p>"
        web.loadHTMLString(MarkdownRenderer.page(body: notice + (DocumentPreviewFormat.kind(for: lastURL) == "markdown" || lastURL == nil ? MarkdownRenderer.render(source) : "<pre>" + source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") + "</pre>"), dark: lastDark), baseURL: URL(string: "mdasset://document/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if fallback { scroll(to: scrollFraction); onRendered?(); return }
        // Module execution can finish after navigation on a custom scheme.
        // Readiness comes from the trusted renderer, not just didFinish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.ready, !self.fallback else { return }
            self.web.evaluateJavaScript("JSON.stringify({errors:window.__mrRendererErrors,url:location.href,scripts:Array.from(document.scripts).map(s=>s.src)})") { [weak self] details, _ in
                self?.rendererError = String(describing: details)
                NSLog("Markdown renderer initialization timed out: %@", String(describing: details))
                self?.renderFallback()
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Markdown provisional navigation failed: %@", String(describing: error))
        if !fallback && (error as NSError).code != NSURLErrorCancelled { renderFallback() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Markdown navigation failed: %@", String(describing: error))
        if !fallback && (error as NSError).code != NSURLErrorCancelled { renderFallback() }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false; loading = false; fallback = false
        if lastText != nil { loadRenderer() }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated {
            if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else {
            let url = action.request.url
            let allowed = action.targetFrame?.isMainFrame == true && (url == MarkdownPreviewResources.indexURL || url?.absoluteString == "about:blank" || (fallback && url?.absoluteString == "mdasset://document/"))
            decisionHandler(allowed ? .allow : .cancel)
        }
    }
    func suspend() {
        revision += 1
        pending?.cancel(); pending = nil
        lastText = nil
        assets.root = nil
        if ready { web.evaluateJavaScript("window.mrPreview.cancel()", completionHandler: nil) }
        // Keep the trusted shell alive, including an in-progress initial load.
        // Stopping it here would strand a reopened preview before didFinish.
        if fallback { fallback = false }
    }
    deinit { pending?.cancel() }
}

private final class MarkdownRendererBridge: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onState: (([String: Any]) -> Void)?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == MarkdownPreviewResources.indexURL else { return }
        if message.body as? String == "ready" { onReady?() }
        else if let state = message.body as? [String: Any] { onState?(state) }
    }
}

final class MarkdownDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDragged(with event: NSEvent) { if let superview { onDrag?(superview.convert(event.locationInWindow, from: nil).x) } }
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { onReset?() } }
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); NSRect(x: bounds.midX, y: 0, width: 1, height: bounds.height).fill() }
}

private final class MarkdownScrollBridge: NSObject, WKScriptMessageHandler {
    var onScroll: ((Double) -> Void)?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let fraction = message.body as? Double, fraction.isFinite else { return }
        onScroll?(max(0, min(1, fraction)))
    }
}

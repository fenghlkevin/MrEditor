import AppKit
import QuickLookUI
import WebKit
import os.log

/// Finder's view-based Quick Look extension. Uses the same offline assets and
/// directory-scoped image handler as the editor, without linking the editor UI.
@objc(MrEditorQuickLookController)
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private let resources = MarkdownPreviewResources()
    private let images = MarkdownAssetHandler()
    private let bridge = QuickLookRendererBridge()
    private var web: WKWebView!
    private var status: NSTextField!
    private var sourceScroll: NSScrollView!
    private var sourceText: NSTextView!
    private var sourceButton: NSButton!
    private var themeButton: NSButton!
    private var zoomResetButton: NSButton!
    private var helpPanel: NSBox?
    private var mouseMonitor: Any?
    private let doubleClickKey = "preview.doubleClickOpensFile"
    private var doubleClickOpensFile: Bool {
        get { UserDefaults.standard.bool(forKey: doubleClickKey) }
        set { UserDefaults.standard.set(newValue, forKey: doubleClickKey) }
    }

    // Unhandled mouse events otherwise bubble to the Quick Look host, which
    // treats a double-click as Open With. Keep the policy local to our preview.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 && !doubleClickOpensFile { return }
        super.mouseDown(with: event)
    }

    @objc private func showPreviewSettings(_ sender: NSButton) {
        let menu = NSMenu()
        let item = NSMenuItem(title: label("双击预览打开文件", "Double-click preview to open file"), action: #selector(toggleDoubleClick), keyEquivalent: "")
        item.target = self
        item.state = doubleClickOpensFile ? .on : .off
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func toggleDoubleClick() {
        doubleClickOpensFile.toggle()
    }

    private var showingSource = false
    private var themeMode = 0
    private var zoom: Double = 1
    private var documentGeneration = 0
    private var chinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") == true }
    private func label(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    private var source: String?
    private var revision = 0
    private var ready = false
    private var recoveryAttempts = 0
    private var scopedURL: URL?
    private var hasScope = false
    private let logger = OSLog(subsystem: "com.aaedit.MrEditor.QuickLook", category: "Preview")

    override func loadView() {
        let root = QuickLookAppearanceView(frame: NSRect(x: 0, y: 0, width: 800, height: 900))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, !self.doubleClickOpensFile, event.clickCount >= 2,
                  event.window === self.view.window else { return event }
            let point = self.view.convert(event.locationInWindow, from: nil)
            // System title-bar controls and the extension toolbar retain their actions.
            guard self.web.frame.contains(point) else { return event }
            return nil
        }
        preferredContentSize = root.frame.size
        root.onAppearanceChanged = { [weak self] in self?.render() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(resources, forURLScheme: MarkdownPreviewResources.scheme)
        configuration.setURLSchemeHandler(images, forURLScheme: "mdasset")
        bridge.onReady = { [weak self] in
            self?.ready = true
            self?.render()
        }
        configuration.userContentController.add(bridge, name: "markdownRenderer")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - 46), configuration: configuration)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.allowsMagnification = true
        root.addSubview(web)
        setupToolbar(in: root)

        status = NSTextField(wrappingLabelWithString: "TextStack · Preview")
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            status.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -48),
        ])
        web.load(URLRequest(url: MarkdownPreviewResources.indexURL))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        _ = view
        documentGeneration += 1
        let token = documentGeneration
        revision += 1
        source = nil
        sourceText.string = ""

        if ready { web.evaluateJavaScript("window.mrPreview.cancel(); document.getElementById('markdown-preview').replaceChildren()", completionHandler: nil) }
        stopScope()
        scopedURL = url
        hasScope = url.startAccessingSecurityScopedResource()
        images.root = url.deletingLastPathComponent()
        status.isHidden = false
        status.stringValue = "TextStack · Preview"
        os_log("Preparing Document Quick Look preview", log: logger, type: .info)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try QuickLookMarkdownDocument.read(url) }
            DispatchQueue.main.async {
                guard let self, self.documentGeneration == token else {
                    handler(CocoaError(.userCancelled)); return
                }
                switch result {
                case .success(let text):
                    self.source = text
                    self.sourceText.string = text
                    self.render()
                    // Let Quick Look present the view while diagrams finish.
                    handler(nil)
                case .failure(let error):
                    self.status.stringValue = error.localizedDescription
                    handler(error)
                }
            }
        }
    }

    // Native controls stay visible while scrolling and never accept actions from document markup.
    private func setupToolbar(in root: NSView) {
        sourceScroll = NSScrollView(frame: web.frame)
        sourceScroll.autoresizingMask = [.width, .height]
        sourceScroll.hasVerticalScroller = true
        sourceScroll.hasHorizontalScroller = false
        sourceScroll.isHidden = true
        sourceText = NSTextView(frame: sourceScroll.bounds)
        sourceText.isEditable = false
        sourceText.isSelectable = true
        sourceText.isRichText = false
        sourceText.autoresizingMask = [.width]
        sourceText.isVerticallyResizable = true
        sourceText.isHorizontallyResizable = false
        sourceText.textContainer?.widthTracksTextView = true
        sourceText.textContainerInset = NSSize(width: 20, height: 16)
        sourceText.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        sourceText.textColor = .textColor
        sourceText.backgroundColor = .textBackgroundColor
        sourceText.setAccessibilityLabel(label("Markdown 源码", "Markdown source"))
        sourceScroll.documentView = sourceText
        root.addSubview(sourceScroll)

        let bar = NSStackView()
        bar.wantsLayer = true
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 6),
            bar.heightAnchor.constraint(equalToConstant: 34),
        ])
        func button(_ symbol: String, _ zh: String, _ en: String, _ action: Selector) -> NSButton {
            let title = label(zh, en)
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
            button.bezelStyle = .circular
            button.contentTintColor = .labelColor
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            bar.addArrangedSubview(button)
            return button
        }
        _ = button("arrow.clockwise", "重新载入文件", "Reload file", #selector(reloadFile))
        _ = button("textformat.size.smaller", "缩小", "Zoom out", #selector(zoomOut))
        zoomResetButton = button("arrow.uturn.backward", "重置缩放（100%）", "Reset zoom (100%)", #selector(resetZoom))
        _ = button("textformat.size.larger", "放大", "Zoom in", #selector(zoomIn))
        _ = button("questionmark.circle", "帮助", "Help", #selector(showHelp(_:)))
        sourceButton = button("doc.text", "查看源码", "Show source", #selector(toggleSource))
        themeButton = button("circle.lefthalf.filled", "主题：跟随系统", "Theme: System", #selector(toggleTheme))
        _ = button("gearshape", "预览设置", "Preview settings", #selector(showPreviewSettings(_:)))
    }

    @objc private func toggleSource() {
        showingSource.toggle()
        sourceScroll.isHidden = !showingSource
        web.isHidden = showingSource
        let title = showingSource ? label("返回预览", "Show preview") : label("查看源码", "Show source")
        sourceButton.image = NSImage(systemSymbolName: showingSource ? "eye" : "doc.text", accessibilityDescription: title)
        sourceButton.toolTip = title
        sourceButton.setAccessibilityLabel(title)
    }
    @objc private func toggleTheme() {
        themeMode = (themeMode + 1) % 3
        view.appearance = themeMode == 0 ? nil : NSAppearance(named: themeMode == 1 ? .aqua : .darkAqua)
        let title = [label("主题：跟随系统", "Theme: System"), label("主题：浅色", "Theme: Light"), label("主题：深色", "Theme: Dark")][themeMode]
        themeButton.image = NSImage(systemSymbolName: ["circle.lefthalf.filled", "sun.max", "moon"][themeMode], accessibilityDescription: title)
        themeButton.toolTip = title
        themeButton.setAccessibilityLabel(title)
        render()
    }
    private func setZoom(_ value: Double) {
        zoom = min(2.5, max(0.5, value))
        web.pageZoom = zoom
        sourceText.font = .monospacedSystemFont(ofSize: 13 * zoom, weight: .regular)
        zoomResetButton.toolTip = label("重置缩放", "Reset zoom") + " (\(Int((zoom * 100).rounded()))%)"
        zoomResetButton.setAccessibilityLabel(zoomResetButton.toolTip)
    }
    @objc private func zoomIn() { setZoom(zoom + 0.1) }
    @objc private func zoomOut() { setZoom(zoom - 0.1) }
    @objc private func resetZoom() { setZoom(1) }
    @objc private func reloadFile() {
        guard let url = scopedURL else { return }
        preparePreviewOfFile(at: url) { [weak self] error in
            guard let self, let error else { return }
            self.status.isHidden = false
            self.status.stringValue = error.localizedDescription
        }
    }
    @objc private func showHelp(_ sender: NSButton) {
        if let panel = helpPanel { panel.removeFromSuperview(); helpPanel = nil; return }
        let text = NSTextField(wrappingLabelWithString: label(
            "文件快速查看\n\n↻ 重新读取磁盘上的文件\n缩小 / 重置 / 放大：50%–250%\n源码：只读查看，再次点击返回预览\n主题：跟随系统 → 浅色 → 深色\n目录：点击页面右上角目录按钮跳转\n再次点击问号关闭帮助。\n\n按空格或 Esc 关闭；编辑请点“通过 TextStack 打开”。",
            "Document Quick Look\n\nReload reads the file from disk.\nZoom out / reset / in: 50%–250%.\nSource toggles a read-only source view.\nTheme cycles System → Light → Dark.\nUse the page’s outline button to jump to headings.\nClick Help again to close this panel.\n\nSpace or Esc closes Quick Look. Use Open with TextStack to edit."))
        let panel = NSBox()
        panel.boxType = .custom
        panel.fillColor = .windowBackgroundColor
        panel.borderColor = .separatorColor
        panel.borderWidth = 1
        panel.cornerRadius = 10
        panel.contentViewMargins = NSSize(width: 16, height: 16)
        panel.translatesAutoresizingMaskIntoConstraints = false
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        let content = panel.contentView!
        content.addSubview(text)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor, constant: 48),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            panel.widthAnchor.constraint(equalToConstant: 342),
            text.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            text.topAnchor.constraint(equalTo: content.topAnchor),
            text.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        helpPanel = panel
    }

    private func render() {
        guard ready, let source else { return }
        revision += 1
        let token = revision
        let options: [String: Any] = [
            "dark": view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            "revision": token, "language": Locale.preferredLanguages.first ?? "en",
            "format": DocumentPreviewFormat.kind(for: scopedURL) ?? "code", "syntax": DocumentPreviewFormat.language(for: scopedURL),
        ]
        web.callAsyncJavaScript("return await window.mrPreview.render(source, options)", arguments: ["source": source, "options": options], in: nil, in: .page) { [weak self] result in
            guard let self, self.revision == token else { return }
            switch result {
            case .success:
                self.status.isHidden = true
                os_log("Document Quick Look rendered", log: self.logger, type: .info)
            case .failure(let error):
                self.status.stringValue = error.localizedDescription
                os_log("Document Quick Look render failed: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.ready else { return }
            self.status.stringValue = "TextStack: Markdown renderer could not be loaded."
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Anchor navigation is handled by the renderer. The Quick Look host owns
        // opening documents; document markup cannot navigate this trusted shell.
        decisionHandler(action.targetFrame?.isMainFrame == true && action.request.url == MarkdownPreviewResources.indexURL ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        guard recoveryAttempts < 1 else {
            status.isHidden = false
            status.stringValue = "TextStack: Markdown renderer could not be started."
            return
        }
        recoveryAttempts += 1
        webView.load(URLRequest(url: MarkdownPreviewResources.indexURL))
    }
    private func stopScope() {
        if hasScope { scopedURL?.stopAccessingSecurityScopedResource() }
        scopedURL = nil; hasScope = false
    }
    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; stopScope() }
}

private final class QuickLookRendererBridge: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == MarkdownPreviewResources.indexURL,
              message.body as? String == "ready" else { return }
        onReady?()
    }
}

private final class QuickLookAppearanceView: NSView {
    var onAppearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        onAppearanceChanged?()
    }
}

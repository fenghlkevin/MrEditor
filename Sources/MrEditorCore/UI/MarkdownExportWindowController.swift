import AppKit
import WebKit
import UniformTypeIdentifiers

final class MarkdownExportWindowController: NSWindowController {
    let preview = MarkdownPreviewView()
    private let status = NSTextField(wrappingLabelWithString: "正在渲染导出预览…")
    private let appearance = NSPopUpButton()
    private let source: String, sourceURL: URL?
    private var buttons: [NSButton] = []
    private(set) var ready = false
    init(source: String, url: URL?) {
        self.source = source; sourceURL = url
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: win); win.title = "Markdown 导出 — " + (url?.lastPathComponent ?? "未保存文档"); setup(); win.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func setup() {
        appearance.addItems(withTitles: ["浅色", "深色"]); appearance.target = self; appearance.action = #selector(render)
        let html = NSButton(title: "导出 HTML…", target: self, action: #selector(exportHTML))
        let pdf = NSButton(title: "导出 PDF…", target: self, action: #selector(exportPDF))
        let png = NSButton(title: "导出长图 PNG…", target: self, action: #selector(exportPNG))
        buttons = [html, pdf, png]; buttons.forEach { $0.isEnabled = false }
        let row = NSStackView(views: [appearance, html, pdf, png]); row.spacing = 12
        preview.usesSharedToolbar = true
        preview.onRendered = { [weak self] in guard let self else { return }; self.ready = true; self.buttons.forEach { $0.isEnabled = true }; self.status.stringValue = "预览已就绪。HTML 内嵌样式、字体和本地图片；PDF 使用 A4 分页；PNG 最多 16000 像素高。" }
        let stack = NSStackView(views: [row, status, preview]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        guard let content = window?.contentView else { return }; content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), preview.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        render()
    }
    @objc private func render() { ready = false; buttons.forEach { $0.isEnabled = false }; status.stringValue = "正在渲染…"; preview.update(source: source, url: sourceURL ?? URL(fileURLWithPath: "/untitled.md"), dark: appearance.indexOfSelectedItem == 1) }
    private func choose(_ type: UTType, completion: @escaping (URL) -> Void) {
        guard ready else { return }; let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = (sourceURL?.deletingPathExtension().lastPathComponent ?? "document") + "." + (type.preferredFilenameExtension ?? "")
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if url.resolvingSymlinksInPath() == self.sourceURL?.resolvingSymlinksInPath() { self.status.stringValue = "请选择其他文件名，不能覆盖 Markdown 源文件。"; return }
            completion(url)
        }
    }
    @objc private func exportHTML() {
        choose(.html) { [weak self] url in self?.writeHTML(to: url) { _ in } }
    }
    func writeHTML(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
            self.preview.web.evaluateJavaScript("""
            (() => {
              const content = (document.querySelector('.markdown-body') || document.body).cloneNode(true);
              content.querySelectorAll('script,.preview-search,.toc-toggle,#toc-container').forEach(n => n.remove());
              content.querySelectorAll('*').forEach(n => Array.from(n.attributes).forEach(a => { if(a.name.startsWith('on')) n.removeAttribute(a.name); }));
              let css = Array.from(document.styleSheets).map(s => { try { return Array.from(s.cssRules).map(r => r.cssText).join('\\n'); } catch { return ''; } }).join('\\n');
              return {body:content.outerHTML,css,theme:document.documentElement.getAttribute('data-theme') || 'light',images:Array.from(content.querySelectorAll('img')).map(n => n.getAttribute('src')).filter(Boolean)};
            })()
            """) { [weak self] object, error in
                guard let self else { return }
                do {
                    if let error { throw error }
                    guard let result = object as? [String: Any], var body = result["body"] as? String, var css = result["css"] as? String else { throw ProcessingError(message: "无法读取渲染结果") }
                    if let root = MarkdownPreviewResources.bundledRoot {
                        let expression = try NSRegularExpression(pattern: #"url\(["']?([^\)"']+)["']?\)"#)
                        let matches = expression.matches(in: css, range: NSRange(location: 0, length: (css as NSString).length))
                        for hit in matches.reversed() {
                            let path = (css as NSString).substring(with: hit.range(at: 1))
                            let name = URL(string: path)?.lastPathComponent ?? path
                            let file = root.appendingPathComponent("assets").appendingPathComponent(name)
                            if ["woff", "woff2", "ttf"].contains(file.pathExtension), let data = try? Data(contentsOf: file) {
                                let mime = file.pathExtension == "ttf" ? "font/ttf" : "font/" + file.pathExtension
                                css = (css as NSString).replacingCharacters(in: hit.range, with: "url('data:\(mime);base64,\(data.base64EncodedString())')")
                            }
                        }
                    }
                    var imageBytes = 0
                    for path in Set(result["images"] as? [String] ?? []) {
                        guard let request = URL(string: path), request.scheme == "mdasset", let root = self.sourceURL?.deletingLastPathComponent(), let file = MarkdownAssetHandler.imageURL(request: request, root: root) else { continue }
                        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20 * 1024 * 1024, imageBytes + size <= 64 * 1024 * 1024 else { throw ProcessingError(message: "本地图片总量超过导出限制（单图 20 MiB / 总计 64 MiB）") }
                        let data = try Data(contentsOf: file); imageBytes += data.count
                        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "image/png"
                        body = body.replacingOccurrences(of: path.replacingOccurrences(of: "&", with: "&amp;"), with: "data:\(mime);base64,\(data.base64EncodedString())")
                    }
                    css = css.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
                    let title = (self.sourceURL?.lastPathComponent ?? "TextStack").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                    let html = "<!doctype html><html data-theme='\(self.appearance.indexOfSelectedItem == 1 ? "dark" : "light")'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'\"><title>\(title)</title><style>\(css)</style></head><body>\(body)</body></html>"
                    try html.write(to: url, atomically: true, encoding: .utf8); self.status.stringValue = "已导出：" + url.path
                    completion(.success(()))
                } catch { self.status.stringValue = error.localizedDescription; completion(.failure(error)) }
            }
    }
    private func renderPDF(completion: @escaping (Result<(Data, [[Double]]), Error>) -> Void) {
        preview.web.callAsyncJavaScript("""
        for (const image of document.images) image.loading = 'eager';
        await document.fonts.ready;
        await Promise.all(Array.from(document.images).map(image => image.complete ? Promise.resolve() : new Promise(resolve => { image.addEventListener('load', resolve, {once:true}); image.addEventListener('error', resolve, {once:true}); setTimeout(resolve, 5000); })));
        return {width:document.documentElement.clientWidth,height:Math.max(document.body.scrollHeight,document.documentElement.scrollHeight),blocks:Array.from(document.querySelectorAll('.markdown-body p,.markdown-body pre,.markdown-body li,.markdown-body tr,.mermaid-diagram,.katex-display,.markdown-body h1,.markdown-body h2,.markdown-body h3')).map(n => { const r=n.getBoundingClientRect(); return [r.top+scrollY,r.bottom+scrollY]; })};
        """, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let object):
                guard let dimensions = object as? [String: Any], let width = dimensions["width"] as? Double, let height = dimensions["height"] as? Double, width > 0, height > 0, height <= 100000 else { completion(.failure(ProcessingError(message: "文档尺寸超过导出限制（高度 100000 像素）"))); return }
                let config = WKPDFConfiguration(); config.rect = NSRect(x: 0, y: 0, width: width, height: height)
                let blocks = dimensions["blocks"] as? [[Double]] ?? []
                self.preview.web.createPDF(configuration: config) { completion($0.map { ($0, blocks) }) }
            }
        }
    }
    @objc private func exportPDF() { choose(.pdf) { [weak self] url in self?.writePDF(to: url) { _ in } } }
    func writePDF(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        status.stringValue = "正在渲染完整 PDF…"
        renderPDF { [weak self] result in
            do { let (data, blocks) = try result.get(); try MarkdownExport.paginate(data, blocks: blocks, to: url); self?.status.stringValue = "已导出：" + url.path; completion(.success(())) }
            catch { self?.status.stringValue = error.localizedDescription; completion(.failure(error)) }
        }
    }
    @objc private func exportPNG() { choose(.png) { [weak self] url in self?.writePNG(to: url) { _ in } } }
    func writePNG(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        status.stringValue = "正在渲染完整长图…"
        renderPDF { [weak self] result in
            do { try MarkdownExport.png(result.get().0, to: url); self?.status.stringValue = "已导出：" + url.path; completion(.success(())) }
            catch { self?.status.stringValue = error.localizedDescription; completion(.failure(error)) }
        }
    }
}

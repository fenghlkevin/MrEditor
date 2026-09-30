import AppKit
import WebKit
import XCTest
@testable import MrEditorCore

@MainActor
final class MarkdownPreviewIntegrationTests: XCTestCase {
    private func evaluate(_ script: String, in web: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func waitFor(_ script: String, in web: WKWebView, timeout: TimeInterval = 30) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if (try? await evaluate(script, in: web)) as? Bool == true { return }
            if let error = (web.superview as? MarkdownPreviewView)?.rendererError {
                XCTFail("Enhanced renderer failed: \(error)")
                throw NSError(domain: "MarkdownPreviewTests", code: 2)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let body = try? await evaluate("document.body.innerText", in: web)
        XCTFail("WebKit preview timed out: \(script)\n\(String(describing: body))")
        throw NSError(domain: "MarkdownPreviewTests", code: 1)
    }

    func testMultipleDocumentFormatsAndSearchInWebKit() async throws {
        _ = NSApplication.shared
        let preview = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 900))
        let window = NSWindow(contentRect: preview.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = preview; window.orderFront(nil)
        defer { preview.suspend(); window.close() }
        let cases: [(String, String, String)] = [
            ("json", "{\"name\":\"alpha\",\"child\":{\"value\":42}}", "document.querySelectorAll('#markdown-preview details').length === 2"),
            ("yaml", "name: alpha\nitems:\n  - one\n  - two", "document.querySelector('#markdown-preview').textContent.includes('alpha')"),
            ("csv", "name,value\nb,10\na,2", "document.querySelectorAll('tbody tr').length === 2"),
            ("tsv", "name\tvalue\na\t2", "document.querySelectorAll('tbody td').length === 2"),
            ("swift", "let answer = 42", "document.querySelector('.source-lines .hljs-keyword') !== null"),
            ("log", "ERROR bad\nWARN retry", "document.querySelector('.log-error') !== null"),
            ("mmd", "flowchart LR\n A[Start] --> B[Done]", "document.querySelector('.mermaid-diagram svg') !== null"),
            ("html", "<h1>Safe HTML</h1><script>window.__unsafe=1</script><img src='https://example.invalid/x'>", "document.querySelector('.html-preview h1')?.textContent === 'Safe HTML' && !window.__unsafe && !document.querySelector('.html-preview img[src]')"),
            ("svg", "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='40'/></svg>", "document.querySelector('.svg-preview circle') !== null"),
            ("md", "# Search\n\nalpha alpha", "document.querySelector('h1')?.textContent === 'Search'"),
        ]
        for (index, entry) in cases.enumerated() {
            preview.update(source: entry.1, url: URL(fileURLWithPath: "/tmp/preview.\(entry.0)"), dark: false)
            try await waitFor("document.querySelector('#markdown-preview')?.dataset.revision === '\(index + 1)'", in: preview.web)
            let success = try await evaluate(entry.2, in: preview.web)
            XCTAssertEqual(success as? Bool, true, entry.0)
        }
        _ = try await evaluate("const f = document.querySelector('.preview-search input'); f.value='alpha'; f.dispatchEvent(new Event('input'))", in: preview.web)
        try await waitFor("document.querySelectorAll('mark[data-preview-search]').length === 2", in: preview.web)
        let current = try await evaluate("document.querySelector('.current-match').textContent", in: preview.web)
        XCTAssertEqual(current as? String, "alpha")
    }

    func testBundledRendererInRealWebKit() async throws {
        _ = NSApplication.shared
        let preview = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 850, height: 1000))
        let window = NSWindow(contentRect: preview.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = preview
        window.orderFront(nil)
        defer { preview.suspend(); window.close() }

        let source = """
        ---
        title: MrEditor Markdown
        ---
        # Markdown 增强预览

        ## 代码、公式与图表

        ```swift
        let greeting = "Hello, Markdown"
        ```

        $$
        E = mc^2
        $$

        ```mermaid
        flowchart LR
            A[Markdown] --> B[MrEditor]
            B --> C[Preview]
        ```

        > [!NOTE]
        > 本地离线渲染，支持公式、图表与目录。

        | 功能 | 状态 |
        | --- | --- |
        | 表格与脚注 | 可用 |

        - [x] 完成渲染

        参考[^1]

        [^1]: 脚注内容
        """
        preview.update(source: source, url: nil, dark: false)
        try await waitFor("document.querySelector('#markdown-preview')?.dataset.revision === '1'", in: preview.web)
        for selector in [".hljs-keyword", ".katex", ".mermaid-diagram svg", ".yaml-frontmatter", ".markdown-alert", ".footnote-ref", ".toc-link", "input[type=checkbox]"] {
            let found = try await evaluate("document.querySelector('\(selector)') !== null", in: preview.web)
            XCTAssertEqual(found as? Bool, true, selector)
        }
        let hasLabels = try await evaluate("document.querySelector('.mermaid-diagram svg').textContent.includes('MrEditor')", in: preview.web)
        XCTAssertEqual(hasLabels as? Bool, true)
        let loadedFonts = try await evaluate("document.fonts.check('16px KaTeX_Main')", in: preview.web)
        XCTAssertEqual(loadedFonts as? Bool, true)
        let light = try await evaluate("getComputedStyle(document.body).backgroundColor", in: preview.web)
        XCTAssertEqual(light as? String, "rgb(255, 255, 255)")

        // Capture the actual native WebKit output for visual verification.
        let snapshot: NSImage = try await withCheckedThrowingContinuation { continuation in
            preview.web.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? NSError(domain: "Snapshot", code: 1)) }
            }
        }
        if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/private/tmp/mreditor-markdown-preview.png"))
        }

        preview.update(source: "# Obsolete", url: nil, dark: false)
        preview.update(source: "# 最终版本\n\n$1+1=2$", url: nil, dark: true)
        try await waitFor("document.querySelector('#markdown-preview')?.dataset.revision === '3'", in: preview.web)
        let dark = try await evaluate("getComputedStyle(document.body).backgroundColor", in: preview.web)
        XCTAssertEqual(dark as? String, "rgb(30, 32, 37)")
        preview.suspend()
        preview.update(source: "# 重新打开", url: nil, dark: false)
        try await waitFor("document.querySelector('h1')?.textContent === '重新打开'", in: preview.web)
        preview.update(source: "# 图表错误不影响正文\n\n```mermaid\nthis is not a diagram\n```", url: nil, dark: false)
        try await waitFor("document.querySelector('.mermaid-diagram details') !== null", in: preview.web)
        XCTAssertNil(preview.rendererError)
    }

    func testUntrustedMarkupCannotExecuteAndLocalImagesStayScoped() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill(); image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("中文 图片.png"))
        let preview = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: preview.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = preview
        window.orderFront(nil)
        defer { preview.suspend(); window.close() }
        let source = """
        # Safe
        <script>window.pwned=1</script>
        <img src="bad.png" onerror="window.pwned=1">
        <iframe src="https://example.com"></iframe>
        <a href="javascript:window.pwned=1">bad</a>

        ![local](<中文 图片.png>)
        ![remote](https://example.com/tracker.png)
        """
        preview.update(source: "# Initial", url: nil, dark: false)
        preview.suspend()
        preview.update(source: source, url: root.appendingPathComponent("test.md"), dark: false)
        try await waitFor("document.querySelector('#markdown-preview')?.dataset.revision === '3'", in: preview.web)
        try await waitFor("document.querySelector('img[alt=local]')?.naturalWidth === \(bitmap.pixelsWide)", in: preview.web)
        let safe = try await evaluate("window.pwned === undefined && !document.querySelector('#markdown-preview script, #markdown-preview iframe, [onerror], a[href^=javascript]')", in: preview.web)
        XCTAssertEqual(safe as? Bool, true)
        let remote = try await evaluate("document.querySelector('img[alt=remote]')?.hasAttribute('src') === false", in: preview.web)
        XCTAssertEqual(remote as? Bool, true)
        let networkBlocked = try await preview.web.callAsyncJavaScript("try { await fetch('https://example.com'); return false; } catch { return true; }", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(networkBlocked as? Bool, true)
    }

    func testResourceHandlerRejectsTraversalAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root.deletingLastPathComponent())
        // URL's symlink resolution is defined for existing targets.
        let outside = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent)-secret.js")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let handler = MarkdownPreviewResources(rootDirectory: root)
        XCTAssertNotNil(handler.resourceURL(for: MarkdownPreviewResources.indexURL))
        for path in ["mdpreview://bundle/../secret.js", "mdpreview://bundle/%2e%2e/secret.js", "mdpreview://bundle/escape/\(outside.lastPathComponent)", "mdpreview://other/index.html", "file:///index.html", "mdpreview://bundle/passwords.key"] {
            XCTAssertNil(handler.resourceURL(for: URL(string: path)!), path)
        }
    }
}

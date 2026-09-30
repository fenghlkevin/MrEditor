import AppKit
import WebKit
import XCTest
@testable import MrEditorCore

/// Real WebKit captures for both app and Quick Look's shared renderer. An optional
/// installed/reference bundle permits side-by-side comparisons without copying
/// any reference implementation into application sources.
@MainActor
final class PreviewAppearanceTests: XCTestCase {
    func testThemesWidthsAndContents() async throws {
        _ = NSApplication.shared
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
        let destination = URL(fileURLWithPath: "/private/tmp/mreditor-preview-comparison", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var roots: [(String, URL?)] = [("after", MarkdownPreviewResources.bundledRoot)]
        if let path = ProcessInfo.processInfo.environment["MREDITOR_PREVIEW_REFERENCE"] {
            roots.insert(("before", URL(fileURLWithPath: path)), at: 0)
        }
        var metrics: [String: Any] = [:]
        for (name, root) in roots {
            for (profile, width, dark) in [("light", 850, false), ("dark", 850, true), ("narrow", 390, false)] {
                let configuration = WKWebViewConfiguration()
                configuration.setURLSchemeHandler(MarkdownPreviewResources(rootDirectory: root), forURLScheme: MarkdownPreviewResources.scheme)
                let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 1000), configuration: configuration)
                let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = web; window.orderFront(nil)
                defer { web.stopLoading(); window.close() }
                web.load(URLRequest(url: MarkdownPreviewResources.indexURL))
                var ready = false
                for _ in 0..<200 {
                    if (try? await web.evaluateJavaScript("!!window.mrPreview")) as? Bool == true { ready = true; break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                XCTAssertTrue(ready, "\(name)-\(profile) initialization")
                guard ready else { continue }
                let rendered = try await web.callAsyncJavaScript("return await window.mrPreview.render(source, {dark, revision:1, language:'zh-Hans'});", arguments: ["source": source, "dark": dark], in: nil, contentWorld: .page)
                XCTAssertEqual(rendered as? Bool, true)
                let state = try await web.evaluateJavaScript("""
                (() => {
                    const selectors = ['h1','h2','pre.hljs','.katex','.mermaid-diagram svg','.markdown-alert','table.yaml-frontmatter'];
                    const result = {};
                    for (const selector of selectors) {
                        const element = document.querySelector(selector);
                        if (!element) throw new Error(selector);
                        const rect = element.getBoundingClientRect();
                        result[selector] = {x:rect.x, y:rect.y, width:rect.width, height:rect.height};
                    }
                    result.background = getComputedStyle(document.body).backgroundColor;
                    result.codeBackground = getComputedStyle(document.querySelector('pre.hljs')).backgroundColor;
                    result.keyword = getComputedStyle(document.querySelector('.hljs-keyword')).color;
                    result.headingText = Array.from(document.querySelectorAll('.toc-link'), e => e.textContent);
                    result.overflow = document.documentElement.scrollWidth > innerWidth;
                    return result;
                })()
                """)
                metrics["\(name)-\(profile)"] = state
                if let state = state as? [String: Any] { XCTAssertEqual(state["overflow"] as? Bool, false) }
                for contentsOpen in [false, true] {
                    if contentsOpen { _ = try await web.evaluateJavaScript("document.querySelector('.toc-toggle').click()") }
                    try await Task.sleep(nanoseconds: 350_000_000)
                    let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                        web.takeSnapshot(with: nil) { image, error in
                            if let image { continuation.resume(returning: image) }
                            else { continuation.resume(throwing: error ?? NSError(domain: "PreviewSnapshot", code: 1)) }
                        }
                    }
                    let bitmap = NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))!
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("\(name)-\(profile)\(contentsOpen ? "-contents" : "").png"))
                }
            }
        }
        try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("metrics.json"))
    }
}

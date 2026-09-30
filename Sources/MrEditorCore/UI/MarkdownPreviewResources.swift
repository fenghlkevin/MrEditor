// Adapted from FluxMarkdown RendererBundleSchemeHandler.swift.
// Copyright (c) 2024-2026 xykong. GPL-3.0; see web-renderer/UPSTREAM.md.
import WebKit
import UniformTypeIdentifiers

final class MarkdownPreviewResources: NSObject, WKURLSchemeHandler {
    static let scheme = "mdpreview"
    static let indexURL = URL(string: "mdpreview://bundle/index.html")!
    let rootDirectory: URL?

    static var bundledRoot: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "MarkdownPreview", withExtension: nil)
        #else
        return Bundle(for: MarkdownPreviewResources.self).url(forResource: "MarkdownPreview", withExtension: nil)
        #endif
    }

    init(rootDirectory: URL? = MarkdownPreviewResources.bundledRoot) {
        self.rootDirectory = rootDirectory?.standardizedFileURL.resolvingSymlinksInPath()
        super.init()
    }

    func resourceURL(for request: URL) -> URL? {
        guard request.scheme == Self.scheme, request.host == "bundle", let rootDirectory else { return nil }
        let file = rootDirectory.appendingPathComponent(request.path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(rootDirectory.path + "/"),
              ["html", "js", "css", "woff", "woff2", "ttf", "txt"].contains(file.pathExtension.lowercased()) else { return nil }
        return file
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let request = task.request.url, let file = resourceURL(for: request),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime: String
        switch file.pathExtension.lowercased() {
        case "js": mime = "application/javascript"
        case "css": mime = "text/css"
        case "html": mime = "text/html"
        default: mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        guard let response = HTTPURLResponse(url: request, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]) else { task.didFailWithError(URLError(.badServerResponse)); return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

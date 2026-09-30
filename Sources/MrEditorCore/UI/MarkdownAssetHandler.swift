import WebKit
import UniformTypeIdentifiers

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


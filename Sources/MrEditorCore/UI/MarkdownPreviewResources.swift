// SPDX-License-Identifier: MIT
import WebKit

/// Read-only catalog of preview assets. Only files found inside the bundle at
/// initialization can be served; a request never supplies a filesystem path.
final class MarkdownPreviewResources: NSObject, WKURLSchemeHandler {
    static let scheme = "mdpreview"
    static let indexURL = URL(string: "mdpreview://bundle/index.html")!
    static var bundledRoot: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: MarkdownPreviewResources.self)
        #endif
        return bundle.url(forResource: "MarkdownPreview", withExtension: nil)
    }

    private struct Asset {
        let url: URL
        let mime: String
    }
    private static let contentTypes = [
        "html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "txt": "text/plain; charset=utf-8",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf"
    ]
    let rootDirectory: URL?
    private var catalog: [String: Asset] = [:]

    init(rootDirectory: URL? = MarkdownPreviewResources.bundledRoot) {
        let root = rootDirectory?.resolvingSymlinksInPath().standardizedFileURL
        self.rootDirectory = root
        super.init()
        guard let root, let files = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for case let entry as URL in files {
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathComponents.starts(with: root.pathComponents),
                  resolved.pathComponents.count > root.pathComponents.count,
                  (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let mime = Self.contentTypes[entry.pathExtension.lowercased()] else { continue }
            let relative = resolved.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            catalog["/" + relative] = Asset(url: resolved, mime: mime)
        }
    }

    private func asset(for url: URL) -> Asset? {
        guard url.scheme == Self.scheme, url.host == "bundle",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        guard let found = catalog[url.path],
              found.url.resolvingSymlinksInPath().standardizedFileURL == found.url else { return nil }
        return found
    }

    func resourceURL(for request: URL) -> URL? { asset(for: request)?.url }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url, let asset = asset(for: url) else {
                throw URLError(.resourceUnavailable)
            }
            let bytes = try Data(contentsOf: asset.url, options: .mappedIfSafe)
            let headers = ["Content-Type": asset.mime, "Content-Length": "\(bytes.count)",
                           "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else {
                throw URLError(.badServerResponse)
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(bytes)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }

    // Delivery above is synchronous on WebKit's callback thread. No work remains
    // queued when WebKit calls stop, so there can be no post-cancellation callback.
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

import Foundation
import CMarkdown

enum MarkdownRenderer {
    // cmark extension registration is global; serialize registration and parsing.
    private static let lock = NSLock()
    static func render(_ source: String) -> String {
        lock.lock(); defer { lock.unlock() }
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(0) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) { _ = cmark_parser_attach_syntax_extension(parser, ext) }
        }
        source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        // Default safe mode omits raw HTML and unsafe URL schemes.
        guard let html = cmark_render_html(document, 0, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }
    static func page(body: String, dark: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src mdasset: data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root{color-scheme: \(dark ? "dark" : "light");--fg:\(dark ? "#e2e5eb" : "#24292f");--bg:\(dark ? "#1e2025" : "#fff");--muted:\(dark ? "#292d34" : "#f5f6f8");--line:\(dark ? "#454b55" : "#d8dee4")}
        *{box-sizing:border-box}body{margin:0;padding:28px 30px 60px;background:var(--bg);color:var(--fg);font:15px/1.7 -apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere}
        h1,h2,h3,h4,h5,h6{line-height:1.3;margin:1.5em 0 .65em;font-weight:650}h1{font-size:28px}h2{font-size:23px;border-bottom:1px solid var(--line);padding-bottom:.35em}body>:first-child{margin-top:0}
        p,ul,ol,pre,blockquote,table{margin:0 0 1em}a{color:#3686ec}code{font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--muted);padding:.15em .35em;border-radius:4px}pre{padding:16px;background:var(--muted);border-radius:8px;overflow:auto}pre code{padding:0;background:none;white-space:pre;overflow-wrap:normal}
        blockquote{border-left:3px solid #7d99b8;padding:4px 16px;color:#7a8695}blockquote p:last-child{margin-bottom:0}table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid var(--line);padding:7px 12px}th{background:var(--muted)}img{max-width:100%;height:auto}hr{border:0;border-top:1px solid var(--line);margin:24px 0}li>p{margin:.4em 0}input[type=checkbox]{margin-right:6px}
        </style></head><body>\(body)</body></html>
        """
    }
}

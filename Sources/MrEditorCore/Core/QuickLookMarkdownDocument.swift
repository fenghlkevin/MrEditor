import Foundation

/// Bounded, read-only loading for the Finder extension's smaller memory budget.
enum QuickLookMarkdownDocument {
    static let byteLimit = 4 * 1024 * 1024
    static func read(_ url: URL, limit: Int = byteLimit) throws -> String {
        let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 4) ?? Data()
        let truncated = data.count > limit || (metadata.fileSize ?? 0) > limit
        let prefix = Data(data.prefix(limit))
        let text: String?
        if prefix.starts(with: [0xff, 0xfe]) || prefix.starts(with: [0xfe, 0xff]) {
            text = String(data: prefix.prefix(prefix.count - prefix.count % 2), encoding: .utf16)
        } else if truncated {
            // A bounded read may stop in the middle of one UTF-8 character.
            text = (0...min(3, prefix.count)).lazy.compactMap { count in
                String(data: prefix.dropLast(count), encoding: .utf8)
            }.first
        } else {
            text = String(data: prefix, encoding: .utf8)
        }
        guard var text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        if text.first == "\u{feff}" { text.removeFirst() }
        if truncated {
            if let newline = text.lastIndex(of: "\n") { text = String(text[..<newline]) }
            let notice = Locale.preferredLanguages.first?.hasPrefix("zh") == true
                ? "文件较大，仅预览开头部分。请在 MrEditor 中打开查看全文。"
                : "Preview truncated. Open in MrEditor to read the complete file."
            text += "\n\n> " + notice
        }
        return text
    }
}

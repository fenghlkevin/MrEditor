import Foundation

struct FolderSearchOptions {
    var query: String
    var replacement: String
    var regex = false
    var caseSensitive = false
    var extensions = ""
}
struct FolderSearchHit {
    let file: Int
    let range: NSRange
    let line: Int
    let before: String
    let after: String
    var selected = true
}
struct FolderSearchFile {
    let url: URL
    let data: Data
    let text: String
    let encoding: String.Encoding
}
struct FolderSearchResult {
    var files: [FolderSearchFile] = []
    var hits: [FolderSearchHit] = []
    var skipped: [String] = []
    var limited = false
}

enum FolderSearch {
    static let fileLimit = 32 * 1024 * 1024
    static let totalLimit = 128 * 1024 * 1024
    static func expression(_ options: FolderSearchOptions) throws -> NSRegularExpression {
        guard !options.query.isEmpty else { throw ProcessingError(message: "请输入搜索内容") }
        return try NSRegularExpression(pattern: options.regex ? options.query : NSRegularExpression.escapedPattern(for: options.query), options: options.caseSensitive ? [] : [.caseInsensitive])
    }
    static func scan(root: URL, options: FolderSearchOptions, cancelled: () -> Bool = { false }) throws -> FolderSearchResult {
        let regex = try expression(options)
        let fm = FileManager.default
        var result = FolderSearchResult(), retained = 0, visited = 0
        let extensions = Set(options.extensions.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty })
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            if result.skipped.count < 100 { result.skipped.append(url.lastPathComponent + ": " + error.localizedDescription) }; return true
        }) else { throw ProcessingError(message: "无法读取目录") }
        for case let url as URL in walker {
            if cancelled() { throw CancellationError() }
            visited += 1
            if visited > 100_000 { result.limited = true; break }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            if !extensions.isEmpty && !extensions.contains(url.pathExtension.lowercased()) { continue }
            guard (values.fileSize ?? 0) <= fileLimit else { if result.skipped.count < 100 { result.skipped.append(url.lastPathComponent + ": 超过 32 MiB") }; continue }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= fileLimit, !data.prefix(4096).contains(0) || data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) else { continue }
                let encoding = EncodingDetector.detect(data).stringEncoding
                guard var text = String(data: data, encoding: encoding), text.data(using: encoding) != nil else { continue }
                // Decode BOM as a transport marker; preserve it in the original bytes when saving.
                if text.hasPrefix("\u{feff}") { text.removeFirst() }
                let ns = text as NSString
                var line = 1, cursor = 0, local: [FolderSearchHit] = []
                regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, stop in
                    if cancelled() { stop.pointee = true; return }
                    guard let match else { return }
                    if result.hits.count + local.count >= 5000 { result.limited = true; stop.pointee = true; return }
                    while cursor < match.range.location {
                        let c = ns.character(at: cursor)
                        if c == 10 || (c == 13 && (cursor + 1 >= ns.length || ns.character(at: cursor + 1) != 10)) { line += 1 }
                        cursor += 1
                    }
                    let replacement = options.regex ? regex.replacementString(for: match, in: text, offset: 0, template: options.replacement) : options.replacement
                    local.append(FolderSearchHit(file: result.files.count, range: match.range, line: line, before: String(ns.substring(with: match.range).prefix(160)), after: String(replacement.prefix(160))))
                }
                if cancelled() { throw CancellationError() }
                if !local.isEmpty {
                    if retained + data.count > totalLimit { result.limited = true; break }
                    retained += data.count
                    result.files.append(FolderSearchFile(url: url, data: data, text: text, encoding: encoding)); result.hits += local
                }
                if result.limited { break }
            } catch is CancellationError { throw CancellationError() }
            catch { if result.skipped.count < 100 { result.skipped.append(url.lastPathComponent + ": " + error.localizedDescription) } }
        }
        return result
    }
    /// Preflight all selected files, back up original bytes, then replace each file atomically.
    /// A later failure is reported with the list already changed; never claim batch atomicity.
    static func replace(result: FolderSearchResult, options: FolderSearchOptions, backup: URL, blockedPaths: Set<String>) throws -> [URL] {
        let regex = try expression(options), fm = FileManager.default
        let selected = Dictionary(grouping: result.hits.filter(\.selected), by: \.file)
        var plans: [(FolderSearchFile, Data)] = []
        for index in selected.keys.sorted() {
            let file = result.files[index]
            guard !blockedPaths.contains(file.url.resolvingSymlinksInPath().path) else { throw ProcessingError(message: "文件已在编辑器打开，请使用“全部已打开文件”的替换预览：\(file.url.path)") }
            let values = try file.url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, try Data(contentsOf: file.url) == file.data else { throw ProcessingError(message: "文件在预览后发生变化，请重新搜索：\(file.url.path)") }
            let ns = NSMutableString(string: file.text)
            let validMatches = regex.matches(in: file.text, range: NSRange(location: 0, length: (file.text as NSString).length))
            let matchesByRange = Dictionary(uniqueKeysWithValues: validMatches.map { ($0.range, $0) })
            for hit in selected[index]!.sorted(by: { $0.range.location > $1.range.location }) {
                guard let match = matchesByRange[hit.range] else { throw ProcessingError(message: "替换预览已失效") }
                let replacement = options.regex ? regex.replacementString(for: match, in: file.text, offset: 0, template: options.replacement) : options.replacement
                ns.replaceCharacters(in: hit.range, with: replacement)
            }
            guard var data = (ns as String).data(using: file.encoding, allowLossyConversion: false) else { throw ProcessingError(message: "替换内容无法使用原文件编码保存：\(file.url.path)") }
            let bom: [UInt8] = file.data.starts(with: [0xef, 0xbb, 0xbf]) ? [0xef, 0xbb, 0xbf] : file.data.starts(with: [0xff, 0xfe]) ? [0xff, 0xfe] : file.data.starts(with: [0xfe, 0xff]) ? [0xfe, 0xff] : []
            if !bom.isEmpty && !data.starts(with: bom) { data.insert(contentsOf: bom, at: 0) }
            plans.append((file, data))
        }
        guard !plans.isEmpty else { throw ProcessingError(message: "请勾选需要替换的匹配项") }
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        var manifest: [String: String] = [:]
        for (index, plan) in plans.enumerated() {
            let name = "\(index)-" + plan.0.url.lastPathComponent
            try plan.0.data.write(to: backup.appendingPathComponent(name), options: .atomic)
            manifest[name] = plan.0.url.path
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: backup.appendingPathComponent("manifest.json"), options: .atomic)
        var changed: [URL] = []
        do {
            for (file, data) in plans {
                guard try Data(contentsOf: file.url) == file.data, try file.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ProcessingError(message: "文件发生变化：\(file.url.path)") }
                let attributes = try fm.attributesOfItem(atPath: file.url.path)
                try data.write(to: file.url, options: .atomic)
                changed.append(file.url)
                if let permissions = attributes[.posixPermissions] { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.url.path) }
            }
        } catch { throw ProcessingError(message: "替换停止，已修改 \(changed.count) 个文件：\(changed.map(\.lastPathComponent).joined(separator: ", "))。原文备份：\(backup.path)\n" + error.localizedDescription) }
        return changed
    }
}

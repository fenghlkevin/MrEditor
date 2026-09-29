import Foundation

/// Record boundaries, not decoded copies of every cell. Quoted CSV newlines belong to their record.
struct RecordIndex {
    let data: Data
    let mode: StructuredMode
    let ranges: [Range<Int>]
    let columnCount: Int
    struct Invalid: LocalizedError {
        let record: Int
        let detail: String
        var errorDescription: String? { "第 \(record) 条记录：\(detail)" }
    }
    static func parse(_ data: Data, mode: StructuredMode, cancelled: () -> Bool = { false }) throws -> RecordIndex {
        precondition([StructuredMode.csv, .tsv, .ndjson].contains(mode))
        return try data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            var ranges: [Range<Int>] = [], maxColumns = 1, columns = 1
            var start = 0, i = 0, quoted = false, afterQuote = false, fieldStart = true
            let delimiter: UInt8 = mode == .tsv ? 9 : 44
            if b.count >= 3 && b[0] == 239 && b[1] == 187 && b[2] == 191 { i = 3; start = 3 }
            func finish(_ end: Int) {
                if mode != .ndjson || b[start..<end].contains(where: { $0 != 32 && $0 != 9 && $0 != 13 }) { ranges.append(start..<end) }
                maxColumns = max(maxColumns, columns); columns = 1; fieldStart = true; afterQuote = false
            }
            while i < b.count {
                if i & 65535 == 0 && cancelled() { throw CancellationError() }
                let c = b[i]
                if mode != .ndjson && quoted {
                    if c == 34 {
                        if i + 1 < b.count && b[i + 1] == 34 { i += 2; continue }
                        quoted = false; afterQuote = true
                    }
                    i += 1; continue
                }
                if c == 10 || c == 13 {
                    finish(i)
                    if c == 13 && i + 1 < b.count && b[i + 1] == 10 { i += 1 }
                    i += 1; start = i; continue
                }
                if mode != .ndjson {
                    if c == delimiter { columns += 1; fieldStart = true; afterQuote = false }
                    else if c == 34 && fieldStart { quoted = true; fieldStart = false }
                    else {
                        if afterQuote || c == 34 { throw Invalid(record: ranges.count + 1, detail: "引号或分隔符不正确") }
                        fieldStart = false
                    }
                }
                i += 1
            }
            if cancelled() { throw CancellationError() }
            if quoted { throw Invalid(record: ranges.count + 1, detail: "字段的引号没有闭合") }
            if start < b.count { finish(b.count) }
            return RecordIndex(data: data, mode: mode, ranges: ranges, columnCount: maxColumns)
        }
    }
    func cells(at row: Int, byteLimit: Int = .max, columns: Range<Int>? = nil) -> [String] {
        guard ranges.indices.contains(row) else { return [] }
        let delimiter: UInt8 = mode == .tsv ? 9 : 44
        return data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            let range = ranges[row]
            var result: [String] = [], cell: [UInt8] = [], quoted = false, i = range.lowerBound, column = 0
            var truncated = false
            func append(_ byte: UInt8) {
                guard columns?.contains(column) ?? true else { return }
                if cell.count < byteLimit { cell.append(byte) } else { truncated = true }
            }
            func finish() {
                if columns?.contains(column) ?? true { result.append(String(decoding: cell, as: UTF8.self) + (truncated ? "…" : "")) }
                cell.removeAll(keepingCapacity: true); truncated = false; column += 1
            }
            while i < range.upperBound {
                let c = b[i]
                if c == 34 {
                    if quoted && i + 1 < range.upperBound && b[i + 1] == 34 { append(34); i += 2; continue }
                    quoted.toggle()
                } else if c == delimiter && !quoted { finish(); if let columns, column >= columns.upperBound { return result } }
                else { append(c) }
                i += 1
            }
            finish(); return result
        }
    }
    /// Pretty printing introduces line breaks, so export as a valid JSON array.
    /// Keep only one parsed record in memory and remove incomplete output on failure.
    func formattedJSON(to url: URL, cancelled: () -> Bool = { false }) throws {
        precondition(mode == .ndjson)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        var completed = false
        defer { try? file.close(); if !completed { try? FileManager.default.removeItem(at: url) } }
        try file.truncate(atOffset: 0)
        try file.write(contentsOf: Data("[".utf8))
        for (row, range) in ranges.enumerated() {
            if cancelled() { throw CancellationError() }
            let record: JSONIndex
            do { record = try JSONIndex.parse(data.subdata(in: range), cancelled: cancelled) }
            catch is CancellationError { throw CancellationError() }
            catch { throw Invalid(record: row + 1, detail: error.localizedDescription) }
            try file.write(contentsOf: Data((row == 0 ? "\n  " : ",\n  ").utf8))
            try record.formatted(to: file, depth: 1, trailingNewline: false, cancelled: cancelled)
        }
        if cancelled() { throw CancellationError() }
        try file.write(contentsOf: Data((ranges.isEmpty ? "]\n" : "\n]\n").utf8))
        completed = true
    }
    func preview(at row: Int) -> String {
        let r = ranges[row]; return String(decoding: data[r.lowerBound..<min(r.upperBound,r.lowerBound + 240)], as: UTF8.self)
    }
}

import Foundation

struct ProcessingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ProcessingResult {
    let url: URL
    let preview: String
    let summary: String
}

/// Writes a complete result while bounding the preview; incomplete output never survives failure.
final class ProcessingOutput {
    let url: URL
    private let file: FileHandle
    private var preview = ""
    private var previewBytes = 0
    private var pending = Data()
    private var complete = false
    init(url: URL) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ProcessingError(message: "无法创建结果文件")
        }
        file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 0)
    }
    deinit { try? file.close(); if !complete { try? FileManager.default.removeItem(at: url) } }
    func write(_ data: Data) throws {
        pending.append(data)
        if pending.count >= 1_048_576 { try file.write(contentsOf: pending); pending.removeAll(keepingCapacity: true) }
        if previewBytes < 65_536 {
            let part = data.prefix(65_536 - previewBytes)
            preview += String(decoding: part, as: UTF8.self)
            previewBytes += part.count
        }
    }
    func finish(summary: String) throws -> ProcessingResult {
        if !pending.isEmpty { try file.write(contentsOf: pending) }
        try file.synchronize(); try file.close(); complete = true
        return ProcessingResult(url: url, preview: preview, summary: summary + " · 预览最多 64 KiB，导出包含完整结果")
    }
}

struct TimeRangeOptions {
    var start: Date?
    var end: Date?
    var format: TimestampFormat?
    var offset: Int
    var year: Int
    var keepContinuation = true

    static func parseBoundary(_ input: String, offset: Int) throws -> Date? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        // DateFormatter validates calendar dates, including month lengths and leap years.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: offset)
            if format.contains("XXXXX") {
                if value.hasSuffix("Z") { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
                else {
                    guard let explicit = try? parseOffset(String(value.suffix(6))) else { continue }
                    formatter.timeZone = TimeZone(secondsFromGMT: explicit)
                }
            }
            if let date = formatter.date(from: value) {
                let canonical = formatter.string(from: date)
                if canonical == value || (canonical.hasSuffix("Z") && String(canonical.dropLast()) + "+00:00" == value) { return date }
            }
        }
        throw ProcessingError(message: "时间格式不正确：\(value)。请输入 yyyy-MM-dd HH:mm:ss[.SSS] 或带时区的 ISO 时间。")
    }

    static func parseOffset(_ text: String) throws -> Int {
        let bytes = Array(text.utf8)
        guard bytes.count == 6, bytes[0] == 43 || bytes[0] == 45, bytes[3] == 58,
              [1, 2, 4, 5].allSatisfy({ (48...57).contains(bytes[$0]) }) else {
            throw ProcessingError(message: "时区请输入 +08:00 或 -05:00")
        }
        let hour = Int(bytes[1] - 48) * 10 + Int(bytes[2] - 48)
        let minute = Int(bytes[4] - 48) * 10 + Int(bytes[5] - 48)
        guard hour <= 14, minute < 60, hour != 14 || minute == 0 else {
            throw ProcessingError(message: "时区必须在 -14:00 到 +14:00 之间")
        }
        return (bytes[0] == 45 ? -1 : 1) * (hour * 3600 + minute * 60)
    }
}

enum TimeRangeProcessor {
    /// Scans bytes once, retaining line endings and continuation lines of matching events.
    static func run(data: Data, options: TimeRangeOptions, output: URL,
                    cancelled: () -> Bool = { false }) throws -> ProcessingResult {
        guard options.start != nil || options.end != nil else { throw ProcessingError(message: "请至少填写开始或结束时间") }
        if let start = options.start, let end = options.end, start > end { throw ProcessingError(message: "开始时间不能晚于结束时间") }
        guard (1...9999).contains(options.year) else { throw ProcessingError(message: "假定年份必须为 1–9999") }
        let writer = try ProcessingOutput(url: output)
        return try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var detector = options.format.map { TimestampDetector(format: $0, timeZoneOffset: options.offset, assumedYear: options.year) }
            if detector == nil {
                var samples: [String] = [], start = 0
                for i in 0..<min(bytes.count, 1_048_576) where bytes[i] == 10 || bytes[i] == 13 {
                    if cancelled() { throw CancellationError() }
                    samples.append(String(decoding: bytes[start..<i], as: UTF8.self)); start = i + 1
                    if samples.count >= 1000 { break }
                }
                if samples.isEmpty { samples = [String(decoding: bytes.prefix(128), as: UTF8.self)] }
                detector = TimestampDetector.detect(sampleLines: samples, timeZoneOffset: options.offset, assumedYear: options.year)
            }
            guard let detector else { throw ProcessingError(message: "未识别到时间戳，请选择日志时间格式后重试（自动检测读取前 1 MiB / 1000 行）") }
            var i = 0, total = 0, kept = 0, dated = 0, matched = false, previous: Date?, year = options.year
            while i < bytes.count {
                if cancelled() { throw CancellationError() }
                let start = i
                while i < bytes.count && bytes[i] != 10 && bytes[i] != 13 {
                    if i & 65535 == 0 && cancelled() { throw CancellationError() }; i += 1
                }
                let end = i
                if i < bytes.count {
                    let cr = bytes[i] == 13; i += 1
                    if cr && i < bytes.count && bytes[i] == 10 { i += 1 }
                }
                total += 1
                var line = UnsafeBufferPointer(rebasing: bytes[start..<end])
                if start == 0 && line.count >= 3 && line[0] == 239 && line[1] == 187 && line[2] == 191 {
                    line = UnsafeBufferPointer(rebasing: line[3...])
                }
                if let components = detector.parseComponents(line) {
                    var date = detector.date(from: components, year: components.year ?? year)
                    if components.year == nil, let prev = previous, date < prev.addingTimeInterval(-2 * 86400) {
                        year += 1; date = detector.date(from: components, year: year)
                    }
                    previous = date; dated += 1
                    matched = (options.start.map { date >= $0 } ?? true) && (options.end.map { date <= $0 } ?? true)
                } else if !options.keepContinuation { matched = false }
                if matched { try writer.write(data.subdata(in: start..<i)); kept += 1 }
            }
            if cancelled() { throw CancellationError() }
            guard dated > 0 else { throw ProcessingError(message: "当前格式未解析到任何时间戳") }
            return try writer.finish(summary: "\(kept) / \(total) 行 · \(dated) 行含时间戳 · 格式 \(detector.format.rawValue) · 起止时间均包含边界")
        }
    }
}


struct CSVCleaningOptions {
    enum EmptyAction: Int { case keep, fill, dropRow }
    enum Conversion: Int { case text, integer, decimal, boolean }
    var mode: StructuredMode = .csv
    var header = true
    /// nil applies to every column; explicit indices are zero based.
    var columns: [Int]?
    var trim = true
    var deduplicate = false
    var emptyAction: EmptyAction = .keep
    var fillValue = ""
    var conversion: Conversion = .text

    static func parseColumns(_ text: String) throws -> [Int]? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        var result: [Int] = []
        for part in parts {
            guard let n = Int(part.trimmingCharacters(in: .whitespaces)), n > 0 else {
                throw ProcessingError(message: "列号必须是从 1 开始的整数，用英文逗号分隔，如 1,3")
            }
            if !result.contains(n - 1) { result.append(n - 1) }
        }
        return result
    }
}

enum CSVCleaningProcessor {
    static func encode(_ cells: [String], mode: StructuredMode) -> Data {
        let delimiter = mode == .tsv ? "\t" : ","
        return Data((cells.map { cell in
            if cell.contains(delimiter) || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") {
                return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return cell
        }.joined(separator: delimiter) + "\n").utf8)
    }

    static func convert(_ value: String, to conversion: CSVCleaningOptions.Conversion) throws -> String {
        switch conversion {
        case .text: return value
        case .integer:
            guard value.range(of: "^[+-]?[0-9]+$", options: .regularExpression) != nil, let number = Int64(value) else {
                throw ProcessingError(message: "不是有效的 64 位整数：\(value.prefix(80))")
            }
            return String(number)
        case .decimal:
            guard value.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", options: .regularExpression) != nil,
                  let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN else {
                throw ProcessingError(message: "不是有效的十进制数：\(value.prefix(80))")
            }
            // Decimal accepts more significant digits than it can preserve; reject lossy conversion.
            let canonical = NSDecimalNumber(decimal: number).stringValue
            guard decimalDigits(value) == decimalDigits(canonical) else {
                throw ProcessingError(message: "十进制转换会丢失精度：\(value.prefix(80))")
            }
            return canonical
        case .boolean:
            switch value.lowercased() {
            case "true", "1", "yes", "y": return "true"
            case "false", "0", "no", "n": return "false"
            default: throw ProcessingError(message: "不是布尔值（true/false、1/0、yes/no）：\(value.prefix(80))")
            }
        }
    }
    private static func decimalDigits(_ value: String) -> String {
        let mantissa = value.lowercased().split(separator: "e")[0]
        let digits = mantissa.filter { $0.isASCII && $0.isNumber }
        return String(digits.drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" }).reversed())
    }

    static func run(data: Data, options: CSVCleaningOptions, output: URL,
                    cancelled: () -> Bool = { false }) throws -> ProcessingResult {
        guard options.mode == .csv || options.mode == .tsv else { throw ProcessingError(message: "请选择 CSV 或 TSV") }
        let index = try RecordIndex.parse(data, mode: options.mode, cancelled: cancelled)
        if let columns = options.columns, columns.contains(where: { $0 < 0 || $0 >= index.columnCount }) {
            throw ProcessingError(message: "列号超出范围，文件共有 \(index.columnCount) 列")
        }
        let writer = try ProcessingOutput(url: output)
        var seen = Set<[String]>(), keyBytes = 0, kept = 0, duplicates = 0, dropped = 0, changed = 0
        for row in index.ranges.indices {
            if cancelled() { throw CancellationError() }
            guard String(data: index.data.subdata(in: index.ranges[row]), encoding: .utf8) != nil else {
                throw ProcessingError(message: "第 \(row + 1) 条记录含无效 UTF-8，取消清洗以避免字符丢失，请确认源文件编码")
            }
            var cells = index.cells(at: row)
            if row == 0 && options.header { try writer.write(encode(cells, mode: options.mode)); continue }
            let original = cells
            let columns = options.columns ?? Array(cells.indices)
            // Explicit missing columns are treated as empty fields, without changing unrelated rows.
            if let maximum = columns.max(), maximum >= cells.count { cells += Array(repeating: "", count: maximum + 1 - cells.count) }
            var discard = false
            for column in columns {
                if options.trim { cells[column] = cells[column].trimmingCharacters(in: .whitespacesAndNewlines) }
                if cells[column].isEmpty {
                    switch options.emptyAction {
                    case .keep: continue
                    case .fill: cells[column] = options.fillValue
                    case .dropRow: discard = true
                    }
                }
            }
            if discard { dropped += 1; continue }
            for column in columns where !cells[column].isEmpty {
                do { cells[column] = try convert(cells[column], to: options.conversion) }
                catch { throw ProcessingError(message: "第 \(row + 1) 条记录，列 \(column + 1)：\(error.localizedDescription)") }
            }
            if options.deduplicate {
                let key = options.columns.map { columns in columns.map { cells[$0] } } ?? cells
                if seen.contains(key) { duplicates += 1; continue }
                keyBytes += key.reduce(64) { $0 + $1.utf8.count + 32 }
                guard keyBytes <= 128 * 1024 * 1024, seen.count < 1_000_000 else {
                    throw ProcessingError(message: "去重键超过内存保护上限（128 MiB / 100 万条），请缩小数据范围或选择更少的去重列")
                }
                seen.insert(key)
            }
            if cells != original { changed += 1 }
            try writer.write(encode(cells, mode: options.mode)); kept += 1
        }
        if cancelled() { throw CancellationError() }
        return try writer.finish(summary: "保留 \(kept) 条 · 修改 \(changed) 条 · 去重 \(duplicates) 条 · 空值删除 \(dropped) 条（表头不计）")
    }
}

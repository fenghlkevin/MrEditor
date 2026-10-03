import Foundation

struct LogFields {
    var values: [String: String]
    static let levelPattern = try! NSRegularExpression(pattern: #"(?i)\b(TRACE|DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL)\b"#)
    static let pairPattern = try! NSRegularExpression(pattern: #"\b([A-Za-z_][A-Za-z0-9_.-]*)\s*[=:]\s*(?:"([^"\r\n]*)"|'([^'\r\n]*)'|([^\s,;\]\}]+))"#)
    static let threadPattern = try! NSRegularExpression(pattern: #"\[([^\[\]]+)\]"#)
    static func parse(_ line: String) -> LogFields {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("at ") || trimmed.hasPrefix("Caused by:") || trimmed.hasPrefix("Suppressed:") || trimmed.hasPrefix("... ") { return LogFields(values: [:]) }
        let ns = line as NSString
        var fields: [String: String] = [:], isJSON = false
        if let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            isJSON = true
            for (key, value) in obj {
                if let s = value as? String { fields[key] = s }
                else if let n = value as? NSNumber { fields[key] = n.stringValue }
            }
        }
        for match in (isJSON ? [] : pairPattern.matches(in: line, range: NSRange(location: 0, length: ns.length))) {
            let range = (2...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }!
            fields[ns.substring(with: match.range(at: 1))] = ns.substring(with: range)
        }
        for (canonical, aliases) in ["level": ["level", "severity", "log.level"], "traceId": ["traceId", "trace_id", "trace.id"], "service": ["service", "serviceName", "service.name"], "thread": ["thread", "threadName", "thread_name"]] {
            for key in aliases { if let value = fields[key] { fields[canonical] = value; break } }
        }
        if fields["level"] == nil, let hit = levelPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) { fields["level"] = ns.substring(with: hit.range(at: 1)) }
        if let level = fields["level"] { fields["level"] = level.uppercased() == "WARNING" ? "WARN" : level.uppercased() }
        if fields["thread"] == nil {
            let brackets = threadPattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if let hit = brackets.first(where: {
                let s = ns.substring(with: $0.range(at: 1)); return s != fields["level"] && !s.contains(":") && !(s.first?.isNumber ?? false)
            }) { fields["thread"] = ns.substring(with: hit.range(at: 1)) }
        }
        return LogFields(values: fields)
    }
    static func timestampText(_ line: String) -> String {
        if let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["timestamp", "time", "@timestamp", "datetime"] {
                if let s = obj[key] as? String { return s }
                if let n = obj[key] as? NSNumber { return n.stringValue }
            }
        }
        return line
    }
}

struct LogAnalysisOptions {
    var bucketSeconds = 60
    var offset = TimeZone.current.secondsFromGMT()
    var year = Calendar(identifier: .gregorian).component(.year, from: Date())
    var format: TimestampFormat?
    var field = "level"
    var value = ""
    var start: Date?
    var end: Date?
}
struct LogBucket {
    let time: Date
    var count = 0
    var errors = 0
    var warnings = 0
    var firstLine = 0
}
struct LogAnalysisResult {
    var total = 0, dated = 0, matched = 0
    var levels: [String: Int] = [:]
    var fields: [String: Int] = [:]
    var buckets: [LogBucket] = []
    var samples: [(Int, String)] = []
    var output: ProcessingResult?
}

enum LogAnalysis {
    /// One UTF-8 line at a time. No full decoded string or array of log records.
    static func lines(data: Data, cancelled: () -> Bool, visit: (Int, String, Range<Int>) throws -> Void) throws {
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self); var pos = 0, number = 0
            while pos < bytes.count {
                if cancelled() { throw CancellationError() }
                let begin = pos
                while pos < bytes.count && bytes[pos] != 10 && bytes[pos] != 13 {
                    if pos & 65535 == 0 && cancelled() { throw CancellationError() }; pos += 1
                }
                guard pos - begin <= 4 * 1024 * 1024 else { throw ProcessingError(message: "单行超过 4 MiB，请先拆分超长日志行") }
                var text = String(decoding: bytes[begin..<pos], as: UTF8.self)
                if begin == 0 && text.hasPrefix("\u{feff}") { text.removeFirst() }
                if pos < bytes.count { let cr = bytes[pos] == 13; pos += 1; if cr && pos < bytes.count && bytes[pos] == 10 { pos += 1 } }
                number += 1; try visit(number, text, begin..<pos)
            }
        }
    }
    static func run(data: Data, options: LogAnalysisOptions, output: URL? = nil, cancelled: () -> Bool = { false }) throws -> LogAnalysisResult {
        guard options.bucketSeconds > 0 else { throw ProcessingError(message: "时间桶必须大于零") }
        if let start = options.start, let end = options.end, start > end { throw ProcessingError(message: "开始时间不能晚于结束时间") }
        var samples: [String] = []
        // A bounded byte sample is enough to identify the dominant timestamp format.
        try lines(data: Data(data.prefix(1_048_576)), cancelled: cancelled) { _, line, _ in if samples.count < 1000 { samples.append(LogFields.timestampText(line)) } }
        let detector = options.format.map { TimestampDetector(format: $0, timeZoneOffset: options.offset, assumedYear: options.year) } ?? TimestampDetector.detect(sampleLines: samples, timeZoneOffset: options.offset, assumedYear: options.year)
        let writer = try output.map { try ProcessingOutput(url: $0) }
        var result = LogAnalysisResult(), buckets: [Int: LogBucket] = [:]
        var previous: Date?, assumedYear = options.year, keepContinuation = false
        try lines(data: data, cancelled: cancelled) { number, line, raw in
            let fields = LogFields.parse(line).values
            result.total += 1
            for key in fields.keys where result.fields.count < 256 || result.fields[key] != nil { result.fields[key, default: 0] += 1 }
            let level = fields["level"] ?? "UNKNOWN"
            if result.levels[level] != nil || result.levels.count < 32 { result.levels[level, default: 0] += 1 }
            var date: Date?
            if let detector, let components = detector.parseComponents(LogFields.timestampText(line)) {
                var parsed = detector.date(from: components, year: components.year ?? assumedYear)
                if components.year == nil, let last = previous, parsed < last.addingTimeInterval(-172800) { assumedYear += 1; parsed = detector.date(from: components, year: assumedYear) }
                date = parsed; previous = parsed; result.dated += 1
            }
            let timeMatches = (options.start == nil && options.end == nil) || date.map { d in (options.start.map { d >= $0 } ?? true) && (options.end.map { d <= $0 } ?? true) } == true
            let fieldMatches = options.value.isEmpty || fields[options.field] == options.value
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let stack = trimmed.hasPrefix("at ") || trimmed.hasPrefix("Caused by:") || trimmed.hasPrefix("Suppressed:") || trimmed.hasPrefix("... ")
            let isContinuation = date == nil && fields["level"] == nil && (fields.isEmpty || stack)
            let matches = isContinuation ? keepContinuation : timeMatches && fieldMatches
            if !isContinuation { keepContinuation = matches }
            if matches {
                result.matched += 1
                if result.samples.count < 1000 { result.samples.append((number, String(line.prefix(2000)))) }
                try writer?.write(data.subdata(in: raw))
                if let date {
                    let key = Int(floor(date.timeIntervalSince1970 / Double(options.bucketSeconds)))
                    guard buckets[key] != nil || buckets.count < 100_000 else { throw ProcessingError(message: "时间桶超过 100000 个，请改用更大的时间粒度") }
                    var bucket = buckets[key] ?? LogBucket(time: Date(timeIntervalSince1970: Double(key * options.bucketSeconds)), firstLine: number)
                    bucket.count += 1; if level == "ERROR" || level == "FATAL" { bucket.errors += 1 }; if level == "WARN" { bucket.warnings += 1 }; buckets[key] = bucket
                }
            }
        }
        result.buckets = buckets.keys.sorted().map { buckets[$0]! }
        result.output = try writer?.finish(summary: "匹配 \(result.matched) / \(result.total) 行（保留堆栈续行）")
        return result
    }
}


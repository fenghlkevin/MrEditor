import Foundation

/// Result ranges use UTF-16, matching NSTextStorage, and follow manual edits between hunk choices.
struct ManualMergeState {
    static let byteLimit = 16 * 1024 * 1024
    let initialText: String
    private(set) var ranges: [Int: NSRange]

    init(model: DiffModel, left: DiffSource, right: DiffSource, adopted: Set<Int>) throws {
        var text = "", positions: [Int: NSRange] = [:], length = 0, bytes = 0
        for (op, operation) in model.ops.enumerated() {
            let block: String
            switch operation {
            case let .equal(_, r, count): block = try Self.lines(right, start: r, count: count)
            default: block = try Self.block(model: model, op: op, source: adopted.contains(op) ? left : right, leftSide: adopted.contains(op))
            }
            bytes += block.utf8.count
            guard bytes <= Self.byteLimit else { throw ProcessingError(message: "手动合并结果超过 16 MiB，请使用按差异块合并并保存，或缩小对比文件。") }
            if case .equal = operation {} else { positions[op] = NSRange(location: length, length: block.utf16.count) }
            text += block; length += block.utf16.count
        }
        initialText = text; ranges = positions
    }
    private static func lines(_ source: DiffSource, start: Int, count: Int) throws -> String {
        var text = "", bytes = 0
        for line in start..<(start + count) {
            let value = source.line(at: line) + "\n"; bytes += value.utf8.count
            guard bytes <= byteLimit else { throw ProcessingError(message: "差异内容超过手动合并的 16 MiB 上限") }
            text += value
        }
        return text
    }
    static func block(model: DiffModel, op: Int, source: DiffSource, leftSide: Bool) throws -> String {
        guard model.ops.indices.contains(op) else { return "" }
        switch model.ops[op] {
        case .equal: return ""
        case let .replace(l, lc, r, rc): return try lines(source, start: leftSide ? l : r, count: leftSide ? lc : rc)
        case let .delete(l, count): return leftSide ? try lines(source, start: l, count: count) : ""
        case let .insert(r, count): return leftSide ? "" : try lines(source, start: r, count: count)
        }
    }
    mutating func didEdit(range: NSRange, replacementLength: Int) {
        let end = NSMaxRange(range), delta = replacementLength - range.length
        for (op, current) in ranges {
            let a = current.location, b = NSMaxRange(current)
            let newStart = a < range.location || (current.length == 0 && a == range.location) ? a : (a >= end ? a + delta : range.location)
            let newEnd = b < range.location ? b : (b >= end ? b + delta : range.location + replacementLength)
            ranges[op] = NSRange(location: max(0, newStart), length: max(0, newEnd - newStart))
        }
    }
    mutating func setRange(_ range: NSRange, for op: Int) { ranges[op] = range }
}

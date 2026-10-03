import Foundation

/// Exact UTF-16 ranges, including original line endings, for the live editable diff.
struct InlineMergeModel {
    struct Lines {
        let text: NSString
        let ranges: [NSRange]
        let hashes: [LineHash]
        init(_ value: String) {
            text = value as NSString
            var ranges: [NSRange] = [], hashes: [LineHash] = []
            var offset = 0
            while offset < text.length {
                var end = 0
                text.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: offset, length: 0))
                let range = NSRange(location: offset, length: end - offset)
                ranges.append(range)
                var hasher = LineHasher()
                // Include endings: adopting a final newline difference must actually resolve it.
                for byte in text.substring(with: range).utf8 { hasher.feed(byte) }
                hashes.append(hasher.value)
                offset = end
            }
            self.ranges = ranges; self.hashes = hashes
        }
        func range(_ start: Int, _ count: Int) -> NSRange {
            let location = start < ranges.count ? ranges[start].location : text.length
            let end = count > 0 ? NSMaxRange(ranges[start + count - 1]) : location
            return NSRange(location: location, length: end - location)
        }
    }
    struct Hunk {
        let left: NSRange
        let right: NSRange
        let leftLines: Range<Int>
        let rightLines: Range<Int>
    }
    let left: Lines
    let right: Lines
    let hunks: [Hunk]
    let ops: [DiffOp]
    init(left: String, right: String) {
        self.left = Lines(left); self.right = Lines(right)
        ops = LineDiff.compute(self.left.hashes, self.right.hashes)
        var hunks: [Hunk] = [], l = 0, r = 0
        for op in ops {
            let lc: Int, rc: Int
            switch op {
            case let .equal(_, _, count): l += count; r += count; continue
            case let .delete(_, count): lc = count; rc = 0
            case let .insert(_, count): lc = 0; rc = count
            case let .replace(_, a, _, b): lc = a; rc = b
            }
            hunks.append(Hunk(left: self.left.range(l, lc), right: self.right.range(r, rc), leftLines: l..<(l + lc), rightLines: r..<(r + rc)))
            l += lc; r += rc
        }
        self.hunks = hunks
    }
    /// Corresponding logical line for synchronized scrolling, interpolating inside changed blocks.
    func correspondingLine(_ line: Double, fromLeft: Bool) -> Double {
        var l = 0, r = 0
        for op in ops {
            let lc: Int, rc: Int
            switch op {
            case let .equal(_, _, n): lc = n; rc = n
            case let .delete(_, n): lc = n; rc = 0
            case let .insert(_, n): lc = 0; rc = n
            case let .replace(_, a, _, b): lc = a; rc = b
            }
            let start = fromLeft ? l : r, count = fromLeft ? lc : rc
            let target = fromLeft ? r : l, targetCount = fromLeft ? rc : lc
            if count > 0 && line < Double(start + count) {
                return Double(target) + max(0, line - Double(start)) * Double(targetCount) / Double(count)
            }
            l += lc; r += rc
        }
        return Double(fromLeft ? r : l)
    }
}

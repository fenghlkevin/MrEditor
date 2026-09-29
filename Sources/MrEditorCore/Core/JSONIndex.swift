import Foundation

/// Byte offsets keep large values out of the object graph. Original spelling and key order survive formatting.
struct JSONIndex {
    struct Node {
        var start: Int
        var end: Int = 0
        var key: Range<Int>?
        var first = -1
        var next = -1
        var count = 0
        var kind: UInt8
    }
    let data: Data
    let nodes: [Node]
    struct Invalid: LocalizedError {
        let offset: Int
        var errorDescription: String? { "JSON 语法错误，字节位置 \(offset + 1)" }
    }
    static func parse(_ data: Data, cancelled: () -> Bool = { false }) throws -> JSONIndex {
        try data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            var i = 0, nodes: [Node] = []
            func fail() -> Invalid { Invalid(offset: i) }
            func check() throws { if cancelled() { throw CancellationError() } }
            func space() { while i < b.count && [9,10,13,32].contains(b[i]) { i += 1 } }
            func string() throws {
                guard i < b.count, b[i] == 34 else { throw fail() }
                i += 1
                while i < b.count {
                    if i & 65535 == 0 { try check() }
                    let c = b[i]; i += 1
                    if c == 34 { return }
                    if c < 32 { throw fail() }
                    if c >= 128 {
                        let extra: Int
                        if (194...223).contains(c) { extra = 1 }
                        else if (224...239).contains(c) { extra = 2 }
                        else if (240...244).contains(c) { extra = 3 }
                        else { throw fail() }
                        guard i + extra <= b.count else { throw fail() }
                        if c == 224 && b[i] < 160 || c == 237 && b[i] > 159 || c == 240 && b[i] < 144 || c == 244 && b[i] > 143 { throw fail() }
                        for _ in 0..<extra { guard (128...191).contains(b[i]) else { throw fail() }; i += 1 }
                    }
                    if c == 92 {
                        guard i < b.count else { throw fail() }
                        let e = b[i]; i += 1
                        if e == 117 {
                            for _ in 0..<4 { guard i < b.count, (48...57).contains(b[i]) || (65...70).contains(b[i]) || (97...102).contains(b[i]) else { throw fail() }; i += 1 }
                        } else if ![34,92,47,98,102,110,114,116].contains(e) { throw fail() }
                    }
                }
                throw fail()
            }
            func value(_ depth: Int, key: Range<Int>? = nil) throws -> Int {
                try check(); space()
                guard depth < 512, i < b.count else { throw fail() }
                let start = i, kind = b[i], id = nodes.count
                nodes.append(Node(start: start, key: key, kind: kind))
                if kind == 123 || kind == 91 {
                    i += 1; space(); let close: UInt8 = kind == 123 ? 125 : 93
                    var previous = -1
                    if i < b.count && b[i] == close { i += 1 } else {
                        while true {
                            space(); var childKey: Range<Int>?
                            if kind == 123 {
                                let k = i; try string(); childKey = k..<i; space()
                                guard i < b.count, b[i] == 58 else { throw fail() }; i += 1
                            }
                            let child = try value(depth + 1, key: childKey)
                            if previous < 0 { nodes[id].first = child } else { nodes[previous].next = child }
                            previous = child; nodes[id].count += 1; space()
                            guard i < b.count else { throw fail() }
                            if b[i] == close { i += 1; break }
                            guard b[i] == 44 else { throw fail() }; i += 1
                        }
                    }
                } else if kind == 34 { try string() }
                else if kind == 116 || kind == 102 || kind == 110 {
                    let word = Array((kind == 116 ? "true" : kind == 102 ? "false" : "null").utf8)
                    for c in word { guard i < b.count, b[i] == c else { throw fail() }; i += 1 }
                } else {
                    if b[i] == 45 { i += 1 }
                    guard i < b.count else { throw fail() }
                    if b[i] == 48 { i += 1 }
                    else { guard (49...57).contains(b[i]) else { throw fail() }; while i < b.count && (48...57).contains(b[i]) { i += 1 } }
                    if i < b.count && b[i] == 46 { i += 1; let p=i; while i < b.count && (48...57).contains(b[i]) { i += 1 }; if i == p { throw fail() } }
                    if i < b.count && (b[i] == 101 || b[i] == 69) { i += 1; if i < b.count && (b[i] == 43 || b[i] == 45) { i += 1 }; let p=i; while i < b.count && (48...57).contains(b[i]) { i += 1 }; if i == p { throw fail() } }
                }
                nodes[id].end = i; return id
            }
            if b.count >= 3 && b[0] == 239 && b[1] == 187 && b[2] == 191 { i = 3 }
            _ = try value(0); space(); guard i == b.count else { throw fail() }
            return JSONIndex(data: data, nodes: nodes)
        }
    }
    func text(_ range: Range<Int>, limit: Int = 400) -> String {
        let end = min(range.upperBound, range.lowerBound + limit)
        return String(decoding: data[range.lowerBound..<end], as: UTF8.self) + (end < range.upperBound ? "…" : "")
    }
    /// Writes incrementally; never constructs a second full document string.
    func formatted(to url: URL, cancelled: () -> Bool = { false }) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        try formatted(to: file, cancelled: cancelled)
    }
    func formatted(to file: FileHandle, depth: Int = 0, trailingNewline: Bool = true, cancelled: () -> Bool = { false }) throws {
        var buffer = Data(); buffer.reserveCapacity(65536)
        func append(_ data: Data) throws { buffer.append(data); if buffer.count >= 65536 { try file.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) } }
        func literal(_ s: String) throws { try append(Data(s.utf8)) }
        func bytes(_ range: Range<Int>) throws {
            var offset = range.lowerBound
            while offset < range.upperBound { if cancelled() { throw CancellationError() }; let end = min(offset + 65536, range.upperBound); try append(data.subdata(in: offset..<end)); offset = end }
        }
        func write(_ id: Int, _ depth: Int) throws {
            if cancelled() { throw CancellationError() }
            let n = nodes[id]
            if let key = n.key { try bytes(key); try literal(": ") }
            if n.kind == 123 || n.kind == 91 {
                try literal(n.kind == 123 ? "{" : "[")
                var child = n.first
                while child >= 0 { try literal("\n" + String(repeating: "  ", count: depth + 1)); try write(child, depth + 1); child = nodes[child].next; if child >= 0 { try literal(",") } }
                if n.count > 0 { try literal("\n" + String(repeating: "  ", count: depth)) }
                try literal(n.kind == 123 ? "}" : "]")
            } else { try bytes(n.start..<n.end) }
        }
        try write(0, depth); if trailingNewline { try literal("\n") }; try file.write(contentsOf: buffer)
    }
}

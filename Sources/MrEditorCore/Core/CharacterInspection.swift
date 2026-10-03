import Foundation

enum CharacterInspection {
    static func report(_ text: String, target: String.Encoding, targetName: String) -> String {
        let scalars = text.unicodeScalars
        var lf = 0, cr = 0, crlf = 0, previousCR = false, position = 0, incompatible = 0, hidden = 0
        var issues: [String] = []
        let suspicious: Set<UInt32> = [0, 0x00a0, 0x200b, 0x200c, 0x200d, 0x2060, 0xfeff, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069]
        var line = 1, column = 1
        for scalar in scalars {
            position += 1
            if scalar.value == 10 { if previousCR { crlf += 1; cr -= 1 } else { lf += 1 } }
            if scalar.value == 13 { cr += 1 }
            let cannotEncode = String(scalar).data(using: target, allowLossyConversion: false) == nil
            if cannotEncode { incompatible += 1 }
            let isHidden = suspicious.contains(scalar.value) || (scalar.properties.generalCategory == .control && ![9, 10, 13].contains(scalar.value))
            if isHidden { hidden += 1 }
            if (cannotEncode || isHidden) && issues.count < 1000 {
                issues.append("行 \(line) · 列 \(column) · " + String(format: "U+%04X", scalar.value) + " · " + (scalar.properties.name ?? "未命名字符") + (cannotEncode ? " · 无法保存为 \(targetName)" : ""))
            }
            if scalar.value == 13 || (scalar.value == 10 && !previousCR) { line += 1; column = 1 } else if scalar.value != 10 { column += 1 }
            previousCR = scalar.value == 13
        }
        let kinds = [lf, cr, crlf].filter { $0 > 0 }.count
        return "Unicode 字符与编码检查\n\n\(position) 个 Unicode 标量 · UTF-8 大小 \(text.utf8.count) 字节\n换行：LF \(lf) · CRLF \(crlf) · CR \(cr)" + (kinds > 1 ? " · 混合换行" : "") + "\n目标编码：\(targetName) · 不兼容字符 \(incompatible) 个\n不可见 / 控制字符 \(hidden) 个（部分字符如 ZWJ 也用于正常文字与表情）\n\n" + (issues.isEmpty ? "未发现不兼容或需检查的不可见字符。" : issues.joined(separator: "\n")) + (hidden + incompatible > 1000 ? "\n显示最多 1000 条位置；统计包含全文。" : "")
    }
}

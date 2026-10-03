import AppKit
import CoreGraphics

enum MarkdownExport {
    static func page(_ data: Data) throws -> CGPDFPage {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider), let page = document.page(at: 1) else { throw ProcessingError(message: "无法读取渲染 PDF") }
        return page
    }
    /// Keep text and vector diagrams intact while slicing the full WebKit PDF onto A4 pages.
    static func paginate(_ data: Data, blocks: [[Double]] = [], to url: URL) throws {
        let source = try page(data), sourceRect = source.getBoxRect(.mediaBox)
        var paper = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let inset: CGFloat = 36, content = paper.insetBy(dx: inset, dy: inset)
        let scale = content.width / sourceRect.width
        guard scale.isFinite, scale > 0, sourceRect.height > 0 else { throw ProcessingError(message: "PDF 尺寸无效") }
        let pageHeight = content.height / scale
        let staging = url.deletingLastPathComponent().appendingPathComponent(".textstack-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let context = CGContext(staging as CFURL, mediaBox: &paper, nil) else { throw ProcessingError(message: "无法创建 PDF") }
        var offset: CGFloat = 0
        while offset < sourceRect.height {
            let target = min(sourceRect.height, offset + pageHeight)
            let crossing = blocks.filter { $0.count == 2 && $0[0] > Double(offset + 1) && $0[0] < Double(target) && $0[1] > Double(target) && $0[1] - $0[0] <= Double(pageHeight) }
            let cut = crossing.map { CGFloat($0[0]) }.min() ?? target
            let segmentHeight = cut - offset
            context.beginPDFPage(nil); context.saveGState()
            context.clip(to: CGRect(x: content.minX, y: content.maxY - segmentHeight * scale, width: content.width, height: segmentHeight * scale))
            context.translateBy(x: inset, y: inset + content.height - (sourceRect.height - offset) * scale)
            context.scaleBy(x: scale, y: scale); context.translateBy(x: -sourceRect.minX, y: -sourceRect.minY)
            context.drawPDFPage(source); context.restoreGState(); context.endPDFPage(); offset = cut
        }
        context.closePDF()
        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: staging) } else { try FileManager.default.moveItem(at: staging, to: url) }
    }
    static func png(_ data: Data, to url: URL) throws {
        let source = try page(data), rect = source.getBoxRect(.mediaBox)
        guard rect.height <= 16000, rect.width <= 4000, rect.height > 0, rect.width > 0 else { throw ProcessingError(message: "长图超过 16000 像素高 / 4000 像素宽，请导出 PDF / HTML") }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(rect.width)), pixelsHigh: Int(ceil(rect.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { throw ProcessingError(message: "无法分配长图内存") }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(origin: .zero, size: rect.size))
        context.translateBy(x: -rect.minX, y: -rect.minY); context.drawPDFPage(source)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ProcessingError(message: "无法生成 PNG") }
        try png.write(to: url, options: .atomic)
    }
}

import AppKit
import WebKit
import PDFKit
import XCTest
@testable import MrEditorCore

@MainActor
final class InvestigationUIIntegrationTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }
        XCTFail("Window operation timed out"); throw ProcessingError(message: "Timed out")
    }
    private func capture(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/textstack-" + name + ".png"))
    }
    func testFeatureWindowsLayoutAndCharacterReport() async throws {
        _ = NSApplication.shared
        let folder = FolderSearchWindowController()
        let log = LogAnalysisWindowController(title: "app.log", loader: { Data("2026-10-03 10:00:00 ERROR service=api\n    at Foo.run(Foo.java:3)\n2026-10-03 10:01:00 WARN service=api".utf8) })
        let characters = CharacterInspectorWindowController(loader: { "中文\u{200b}\r\nabc\n" })
        let windows: [(NSWindowController, String)] = [(folder, "folder"), (log, "log"), (characters, "characters")]
        for (controller, _) in windows { controller.window?.isReleasedWhenClosed = false; controller.showWindow(nil) }
        defer { windows.forEach { $0.0.close() } }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        for (controller, name) in windows { try capture(try XCTUnwrap(controller.window), name: name) }
        // Exercise the actual button path, including its background analysis and table population.
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(log.window!.contentView!)
        let run = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "分析 / 筛选" })
        run.performClick(nil)
        let tables = views.compactMap { $0 as? NSTableView }
        try await waitUntil { tables.map(\.numberOfRows).sorted() == [2, 3] }
        try capture(log.window!, name: "log-results")
    }
    func testMarkdownExportsAreRenderedPortableAndPaginated() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("textstack-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try image.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("image.png"))
        let source = "# 导出验证\n\n$x^2 + y^2 = z^2$\n\n![local](image.png)\n\n```mermaid\ngraph LR\n A[输入] --> B[输出]\n```\n\n<script>alert('unsafe')</script>\n" + (1...70).map { "\n\n段落 \($0)：TextStack 导出测试。" }.joined()
        let controller = MarkdownExportWindowController(source: source, url: directory.appendingPathComponent("source.md"))
        controller.window?.isReleasedWhenClosed = false; controller.showWindow(nil)
        defer { controller.preview.suspend(); controller.close() }
        try await waitUntil { controller.ready }
        let htmlURL = directory.appendingPathComponent("output.html")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in controller.writeHTML(to: htmlURL) { c.resume(with: $0) } }
        let html = try String(contentsOf: htmlURL)
        XCTAssertTrue(html.contains("data:font/woff2;base64,")); XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertTrue(html.contains("mermaid-diagram")); XCTAssertTrue(html.contains("<svg")); XCTAssertTrue(html.contains("katex"))
        XCTAssertFalse(html.contains("<script")); XCTAssertFalse(html.contains("mdasset://")); XCTAssertFalse(html.contains("mdpreview://"))
        let pdfURL = directory.appendingPathComponent("output.pdf")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in controller.writePDF(to: pdfURL) { c.resume(with: $0) } }
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL)); XCTAssertGreaterThan(pdf.pageCount, 1)
        try pdf.string?.write(to: URL(fileURLWithPath: "/tmp/textstack-export-pdf-text.txt"), atomically: true, encoding: .utf8)
        try Data(contentsOf: pdfURL).write(to: URL(fileURLWithPath: "/tmp/textstack-export-verified.pdf"))
        XCTAssertTrue(pdf.string?.filter { !$0.isWhitespace }.contains("段落70") == true)
        let pngURL = directory.appendingPathComponent("output.png")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in controller.writePNG(to: pngURL) { c.resume(with: $0) } }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: pngURL))); XCTAssertGreaterThan(bitmap.pixelsHigh, 1000)
        try Data(contentsOf: pngURL).write(to: URL(fileURLWithPath: "/tmp/textstack-markdown-export.png"))
        try capture(controller.window!, name: "markdown-export-window")
    }
}

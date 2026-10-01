import AppKit
import XCTest
@testable import MrEditorCore

@MainActor
final class PreviewOnlyTests: XCTestCase {
    func testPreviewOnlyLayoutAndRestorePreserveDocument() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-only-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = "# Preview\n\nDocument content"
        try source.write(to: url, atomically: true, encoding: .utf8)
        let viewer = EditableViewer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        XCTAssertTrue(viewer.open(url: url))
        viewer.layoutSubtreeIfNeeded()
        let preview = try XCTUnwrap(viewer.subviews.compactMap { $0 as? MarkdownPreviewView }.first)
        let editor = try XCTUnwrap(viewer.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(preview.frame.width, 500, accuracy: 1)
        viewer.togglePreviewOnly()
        viewer.layoutSubtreeIfNeeded()
        XCTAssertTrue(editor.isHidden)
        XCTAssertEqual(preview.frame.width, 1000, accuracy: 1)
        XCTAssertEqual(viewer._testText, source)
        XCTAssertFalse(viewer.isDirty)
        viewer.togglePreviewOnly()
        viewer.layoutSubtreeIfNeeded()
        XCTAssertFalse(editor.isHidden)
        XCTAssertEqual(preview.frame.width, 500, accuracy: 1)
        viewer.togglePreviewOnly()
        viewer.setMarkdownPreviewVisible(false)
        viewer.layoutSubtreeIfNeeded()
        XCTAssertFalse(editor.isHidden)
        XCTAssertTrue(preview.isHidden)
        XCTAssertEqual(editor.frame.width, 1000, accuracy: 1)
    }
}

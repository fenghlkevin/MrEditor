import AppKit
import XCTest
@testable import MrEditorCore

final class InspectorSyncTests: XCTestCase {
    func testPieceSnapshotRemainsStableWhileEditingContinues() throws {
        let table = PieceTable(bytes: Array("{\"name\":\"中文\"}".utf8))
        table.insert(Array("\n".utf8), at: 0)
        let snapshot = table.inspectorSnapshot()
        table.delete(0..<1)
        table.insert(Array(" ".utf8), at: 0)
        XCTAssertEqual(String(decoding: try snapshot { false }, as: UTF8.self), "\n{\"name\":\"中文\"}")
        XCTAssertThrowsError(try snapshot { true })
    }
    func testSourcePositionUsesUTF8OffsetsAndUTF16Caret() {
        _ = NSApplication.shared
        let pane = EditableViewer(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let prefix = "{\"中文😀\":1,"
        pane._testSetText(prefix + "\"next\":2}")
        let revision = pane.contentRevision
        pane.revealSourceByteOffset(prefix.utf8.count)
        XCTAssertEqual(pane._testSelection.location, prefix.utf16.count)
        XCTAssertEqual(pane.contentRevision, revision, "Caret movement must not trigger a preview rebuild")
        pane._testSetText("{}")
        XCTAssertGreaterThan(pane.contentRevision, revision)
    }
}

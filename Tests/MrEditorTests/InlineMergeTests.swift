import XCTest
import AppKit
@testable import MrEditorCore

final class InlineMergeTests: XCTestCase {
    private func adopted(_ left: String, _ right: String) -> String {
        let model = InlineMergeModel(left: left, right: right)
        let result = NSMutableString(string: right)
        for hunk in model.hunks.reversed() { result.replaceCharacters(in: hunk.right, with: model.left.text.substring(with: hunk.left)) }
        return result as String
    }
    func testExactAdoptionForEmptyInsertDeleteUnicodeAndLineEndings() {
        for (left, right) in [("", "one\n"), ("one\n", ""), ("a\n左😀\ntail", "a\nright\nextra\ntail\n"), ("a\r\nb\r\n", "a\nb\n"), ("a\n", "a"), ("a", "a\n"), ("\n\n", "")] {
            XCTAssertEqual(adopted(left, right), left)
            XCTAssertTrue(InlineMergeModel(left: left, right: adopted(left, right)).hunks.isEmpty)
        }
    }
    func testRangesAreRecomputedAfterManualEdit() {
        let initial = InlineMergeModel(left: "header\nleft\ntail\n", right: "header\nright\ntail\n")
        let edited = InlineMergeModel(left: "header\nleft\ntail\n", right: "custom😀\nheader\nright\ntail\n")
        XCTAssertEqual(edited.hunks.count, 2)
        XCTAssertEqual(edited.right.text.substring(with: edited.hunks[1].right), "right\n")
        XCTAssertGreaterThan(edited.hunks[1].right.location, initial.hunks[0].right.location)
    }
    func testScrollMappingAcrossUnequalBlocks() {
        let model = InlineMergeModel(left: "header\na\nb\nc\ntail\n", right: "header\nx\ntail\n")
        XCTAssertEqual(model.correspondingLine(4, fromLeft: true), 2)
        XCTAssertEqual(model.correspondingLine(2, fromLeft: false), 4)
    }
    func testSnapshotPreservesOriginalTextAndHonorsBudget() {
        let source = TextDiffSource(text: "a\r\n😀", displayName: "test")
        XCTAssertEqual(source.editableSnapshot(limit: 20), "a\r\n😀")
        XCTAssertNil(source.editableSnapshot(limit: 3))
    }
    func testNativeEditorLayoutHighlightAndUndo() throws {
        _ = NSApplication.shared
        let left = "import Foundation\n\nfunc fetch() async throws {\n    let response = try await Task.detached {\n        try client.send(config: config)\n    }.value\n    print(response)\n}\n"
        let right = "import Foundation\n\nfunc fetch() async throws {\n    let response = try await sendOnBackground(client: client)\n    print(response)\n}\n"
        let text = MergeCodeView(); text.string = right
        let view = InlineMergeView(left: left, rightEditor: text, fileName: "HttpService.swift")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 550), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; window.makeFirstResponder(text)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.leftEditor.isEditable); XCTAssertTrue(text.isEditable)
        XCTAssertEqual(view.model.hunks.count, 1)
        XCTAssertGreaterThan(text.enclosingScrollView?.frame.width ?? 0, 600)
        XCTAssertNotNil(text.layoutManager?.temporaryAttributes(atCharacterIndex: 0, effectiveRange: nil)[.foregroundColor])
        view.adoptSelected(); XCTAssertEqual(text.string, left)
        let updated = expectation(for: NSPredicate { _,_ in !view.updating }, evaluatedWith: nil)
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(view.model.hunks.count, 0)
        text.undoManager?.undo(); XCTAssertEqual(text.string, right)
        let undone = expectation(for: NSPredicate { _,_ in !view.updating }, evaluatedWith: nil)
        wait(for: [undone], timeout: 5)
        XCTAssertEqual(view.model.hunks.count, 1)
        if let path = ProcessInfo.processInfo.environment["MERGE_RENDER_PATH"] {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

}

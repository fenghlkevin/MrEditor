import XCTest
import AppKit
@testable import MrEditorCore

final class ManualMergeTests: XCTestCase {
    private func sources() -> (TextDiffSource, TextDiffSource, DiffModel) {
        let left = TextDiffSource(text: "header\n左😀\nmiddle\nleft-only\ntail\n", displayName: "left")
        let right = TextDiffSource(text: "header\nright\nmiddle\ntail\nextra\n", displayName: "right")
        return (left, right, DiffModel(ops: LineDiff.compute(left.lineHashes(), right.lineHashes())))
    }
    func testInitialResultUsesRightAndAdoptedHunks() throws {
        let (l,r,m) = sources()
        let state = try ManualMergeState(model: m, left: l, right: r, adopted: [m.hunkOpIndices[0]])
        XCTAssertEqual(state.initialText, "header\n左😀\nmiddle\ntail\nextra\n")
        let range = try XCTUnwrap(state.ranges[m.hunkOpIndices[0]])
        XCTAssertEqual((state.initialText as NSString).substring(with: range), "左😀\n")
    }
    func testManualEditsBeforeHunksMoveRangesWithoutLosingContent() throws {
        let (l,r,m) = sources(); var state = try ManualMergeState(model: m, left: l, right: r, adopted: [])
        let range = try XCTUnwrap(state.ranges[m.hunkOpIndices[0]])
        state.didEdit(range: NSRange(location: 0, length: 0), replacementLength: 3)
        XCTAssertEqual(state.ranges[m.hunkOpIndices[0]]?.location, range.location + 3)
        state.didEdit(range: NSRange(location: range.location + 3, length: range.length), replacementLength: 8)
        XCTAssertEqual(state.ranges[m.hunkOpIndices[0]]?.length, 8)
    }
    func testDeletionAndUndoRestoreTargetRange() throws {
        let (l,r,m) = sources(); var state = try ManualMergeState(model: m, left: l, right: r, adopted: [])
        let op = m.hunkOpIndices[0], range = try XCTUnwrap(state.ranges[m.hunkOpIndices[0]])
        state.didEdit(range: range, replacementLength: 0)
        XCTAssertEqual(state.ranges[op], NSRange(location: range.location, length: 0))
        state.didEdit(range: NSRange(location: range.location, length: 0), replacementLength: range.length)
        XCTAssertEqual(state.ranges[op], range)
    }
    func testLeftOnlyAndRightOnlyChoicesHaveEmptyAlternative() throws {
        let (l,r,m) = sources()
        let hunks = m.hunkOpIndices
        XCTAssertEqual(try ManualMergeState.block(model: m, op: hunks[1], source: l, leftSide: true), "left-only\n")
        XCTAssertEqual(try ManualMergeState.block(model: m, op: hunks[1], source: r, leftSide: false), "")
        XCTAssertEqual(try ManualMergeState.block(model: m, op: hunks[2], source: l, leftSide: true), "")
        XCTAssertEqual(try ManualMergeState.block(model: m, op: hunks[2], source: r, leftSide: false), "extra\n")
    }
    func testSizeBudgetRejectsHugeEditableResults() {
        let source = TextDiffSource(text: String(repeating: "x", count: ManualMergeState.byteLimit + 1), displayName: "large")
        let model = DiffModel(ops: [.equal(left: 0, right: 0, count: 1)])
        XCTAssertThrowsError(try ManualMergeState(model: model, left: source, right: source, adopted: []))
    }
    func testViewerTypingHunkChoiceUndoAndDraftProtection() throws {
        _ = NSApplication.shared
        let viewer = DiffViewer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = viewer
        viewer.draftStore = DraftStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { viewer.discardDraft(); try? FileManager.default.removeItem(at: viewer.draftStore.root) }
        let compared = expectation(description: "compare")
        viewer.onCompared = { compared.fulfill() }
        viewer.beginCompare(title: "test", makeSources: { let (l,r,_) = self.sources(); return (l,r) }, onFailure: { XCTFail($0) })
        wait(for: [compared], timeout: 5)
        viewer.startManualMerge()
        let ready = expectation(for: NSPredicate { _,_ in viewer.manualMergeActive }, evaluatedWith: nil)
        wait(for: [ready], timeout: 5)
        XCTAssertTrue(viewer.canEdit); XCTAssertFalse(viewer.isDirty)
        XCTAssertNil(viewer.restorableText)
        let session = SessionState.make(docs: [(url: viewer.fileURL, text: viewer.restorableText, draftID: viewer.draftID, dirty: viewer.isDirty)], activeIndex: 0)
        XCTAssertTrue(session.entries.isEmpty)
        viewer.mergeTextView.insertText("custom\n", replacementRange: NSRange(location: 0, length: 0))
        let updated = expectation(for: NSPredicate { _,_ in viewer.inlineMerge?.updating == false }, evaluatedWith: nil)
        wait(for: [updated], timeout: 5)
        viewer.mergeTextView.setSelectedRange((viewer.mergeTextView.string as NSString).range(of: "right"))
        viewer.adoptCurrentHunk()
        XCTAssertEqual(viewer.mergeTextView.string, "custom\nheader\n左😀\nmiddle\ntail\nextra\n")
        viewer.mergeTextView.undoManager?.undo()
        XCTAssertTrue(viewer.mergeTextView.string.contains("header\nright\n"))
        let undone = expectation(for: NSPredicate { _,_ in viewer.inlineMerge?.updating == false }, evaluatedWith: nil)
        wait(for: [undone], timeout: 5)
        viewer.mergeTextView.setSelectedRange((viewer.mergeTextView.string as NSString).range(of: "right"))
        viewer.adoptCurrentHunk()
        viewer.revertCurrentHunk()
        XCTAssertTrue(viewer.mergeTextView.string.contains("header\nright\n"))
        viewer.mergeTextView.undoManager?.undo() // Remove the custom prefix; the result is now pristine.
        XCTAssertFalse(viewer.isDirty)
        XCTAssertNil(viewer.draftID)
        XCTAssertNil(viewer.restorableText)
        XCTAssertTrue(viewer.canToggleFormatCompare)
        viewer.mergeTextView.insertText("draft note\n", replacementRange: NSRange(location: 0, length: 0))
        viewer.flushDraft()
        XCTAssertEqual(MergeSideDraft.decode(try XCTUnwrap(viewer.draftStore.read(id: try XCTUnwrap(viewer.draftID))))?.displayName, "right")
        XCTAssertEqual(MergeSideDraft.decode(try XCTUnwrap(viewer.draftStore.read(id: try XCTUnwrap(viewer.draftID))))?.text, viewer.mergeTextView.string)
    }
}

import AppKit
import XCTest
@testable import MrEditorCore

final class WindowFrameTests: XCTestCase {
    func testOversizedRestoredWindowFitsVisibleScreen() {
        let screen = NSRect(x: 0, y: 60, width: 1440, height: 815)
        let frame = MainWindowController.boundedWindowFrame(NSRect(x: -200, y: -100, width: 2600, height: 1800), visible: screen)
        XCTAssertEqual(frame, screen)
    }
    func testNormalFrameIsPreservedAndSecondaryScreenOriginIsRespected() {
        let screen = NSRect(x: -1920, y: 40, width: 1920, height: 1040)
        let normal = NSRect(x: -1800, y: 100, width: 1000, height: 700)
        XCTAssertEqual(MainWindowController.boundedWindowFrame(normal, visible: screen), normal)
        let offscreen = NSRect(x: 300, y: 900, width: 1000, height: 700)
        XCTAssertEqual(MainWindowController.boundedWindowFrame(offscreen, visible: screen), NSRect(x: -1000, y: 380, width: 1000, height: 700))
    }
}

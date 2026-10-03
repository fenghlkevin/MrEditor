import XCTest
@testable import MrEditorCore

final class DefaultPreviewTypesTests: XCTestCase {
    func testConfiguredTypes() {
        func opens(_ name: String, _ types: String) -> Bool {
            AppSettings.shouldOpenPreview(for: URL(fileURLWithPath: "/tmp/" + name), types: types)
        }
        XCTAssertTrue(opens("README.MD", "md, json"))
        XCTAssertTrue(opens("data.json", ".MD，*.json"))
        XCTAssertFalse(opens("file.html", "md,json"))
        XCTAssertFalse(opens("file.md", ""))
        XCTAssertTrue(opens("file.html", "*"))
        XCTAssertFalse(opens("file.png", "*"))
        XCTAssertTrue(opens("Dockerfile", "dockerfile"))
        XCTAssertTrue(opens(".env", ".env"))
    }
}

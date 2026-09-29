import XCTest
@testable import MrEditorCore

final class MarkdownRendererTests: XCTestCase {
    func testCommonMarkAndExtensions() {
        let html = MarkdownRenderer.render("# 中文标题\n\n**粗体** ~~删除~~\n\n- [x] 完成\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1 < 2\n```\n")
        for expected in ["<h1>中文标题</h1>", "<strong>粗体</strong>", "<del>删除</del>", "type=\"checkbox\"", "<table>", "language-swift", "1 &lt; 2"] { XCTAssertTrue(html.contains(expected), expected + html) }
    }
    func testUnsafeHTMLAndLinksCannotExecute() {
        let html = MarkdownRenderer.render("<script>alert(1)</script>\n\n[bad](javascript:alert)\n\n![local](image.png)")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("src=\"image.png\""))
    }
    func testImagePathsStayInsideDocumentDirectory() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(MarkdownAssetHandler.imageURL(request: URL(string: "mdasset://document/images/a.png")!, root: root)?.path, root.appendingPathComponent("images/a.png").path)
        XCTAssertNil(MarkdownAssetHandler.imageURL(request: URL(string: "mdasset://document/../../secret.png")!, root: root))
        XCTAssertNil(MarkdownAssetHandler.imageURL(request: URL(string: "mdasset://document/key.txt")!, root: root))
    }
}

import XCTest
@testable import MrEditorCore

final class JSONIndexTests: XCTestCase {
    func testTreePreservesDuplicateKeysOrderAndExactNumbers() throws {
        let source = #"{"z":9007199254740993,"z":1.2300e+40,"a":[true,null,{"name":"中文"}]}"#
        let index = try JSONIndex.parse(Data(source.utf8))
        XCTAssertEqual(index.nodes[0].count, 3)
        let first = index.nodes[0].first
        XCTAssertEqual(index.text(index.nodes[first].start..<index.nodes[first].end), "9007199254740993")
        XCTAssertEqual(index.nodes[index.nodes[first].next].next, 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try index.formatted(to: url)
        let text = try String(contentsOf: url)
        XCTAssertTrue(text.contains("1.2300e+40"))
        XCTAssertTrue(text.contains("9007199254740993"))
        XCTAssertTrue(text.contains("中文"))
        XCTAssertEqual(try JSONIndex.parse(Data(text.utf8)).nodes.count, index.nodes.count)
    }
    func testRejectsInvalidGrammar() {
        for source in ["", "{", "[1,]", "{\"x\":}", "01", "1e", "-", "true false", "{\"x\" 1}", "\"\\q\"", "\"\\uQQQQ\"", "\"line\nfeed\""] {
            XCTAssertThrowsError(try JSONIndex.parse(Data(source.utf8)), source)
        }
    }
    func testTopLevelScalarsAndEmptyContainers() throws {
        for source in ["null", "true", "false", "-1.2e-4", "\"a\\\"b\"", "{}", "[]"] { XCTAssertEqual(try JSONIndex.parse(Data(source.utf8)).nodes.count, 1) }
    }
    func testRejectsInvalidUTF8String() {
        XCTAssertThrowsError(try JSONIndex.parse(Data([34, 255, 34])))
        XCTAssertThrowsError(try JSONIndex.parse(Data([34, 224, 128, 128, 34])))
        XCTAssertNoThrow(try JSONIndex.parse(Data("\"😀中文\"".utf8)))
    }
    func testCancellationAndExcessiveDepth() {
        XCTAssertThrowsError(try JSONIndex.parse(Data("[]".utf8), cancelled: { true }))
        XCTAssertThrowsError(try JSONIndex.parse(Data((String(repeating: "[", count: 600) + "0" + String(repeating: "]", count: 600)).utf8)))
    }
    func testMappedLargeJSONAndStreamingFormatting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("large.json"), output = folder.appendingPathComponent("formatted.json")
        FileManager.default.createFile(atPath: source.path, contents: Data("[".utf8))
        let file = try FileHandle(forWritingTo: source); try file.seekToEnd()
        let item = Data(("{\"id\":9007199254740993,\"body\":\"" + String(repeating: "a", count: 4096) + "\"}").utf8)
        for i in 0..<25000 { if i > 0 { try file.write(contentsOf: Data([44])) }; try file.write(contentsOf: item) }
        try file.write(contentsOf: Data([93])); try file.close()
        let data = try Data(contentsOf: source, options: .alwaysMapped)
        XCTAssertGreaterThan(data.count, 100_000_000)
        let index = try JSONIndex.parse(data)
        XCTAssertEqual(index.nodes[0].count, 25000)
        XCTAssertEqual(index.nodes.count, 75001)
        try index.formatted(to: output)
        let reparsed = try JSONIndex.parse(Data(contentsOf: output, options: .alwaysMapped))
        XCTAssertEqual(reparsed.nodes.count, index.nodes.count)
        XCTAssertEqual(reparsed.nodes[0].count, 25000)
    }
}

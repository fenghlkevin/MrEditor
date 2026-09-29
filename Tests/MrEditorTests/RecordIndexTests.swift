import XCTest
@testable import MrEditorCore

final class RecordIndexTests: XCTestCase {
    func testCSVQuotedMultilineAndEscapes() throws {
        let text = "\u{feff}name,note,tail\r\n中文,\"first\r\nsecond,\"\"quoted\"\"\",\r\nlast,plain,end"
        let index = try RecordIndex.parse(Data(text.utf8), mode: .csv)
        XCTAssertEqual(index.ranges.count, 3)
        XCTAssertEqual(index.columnCount, 3)
        XCTAssertEqual(index.cells(at: 0), ["name", "note", "tail"])
        XCTAssertEqual(index.cells(at: 1), ["中文", "first\r\nsecond,\"quoted\"", ""])
        XCTAssertEqual(index.cells(at: 2), ["last", "plain", "end"])
    }
    func testTSVAndUnevenColumns() throws {
        let index = try RecordIndex.parse(Data("a\tb\n1\t\"two\tthree\"\n4\t5\t6\t".utf8), mode: .tsv)
        XCTAssertEqual(index.columnCount, 4)
        XCTAssertEqual(index.cells(at: 1), ["1", "two\tthree"])
        XCTAssertEqual(index.cells(at: 2), ["4", "5", "6", ""])
    }
    func testEmptyAndBlankRecords() throws {
        XCTAssertEqual(try RecordIndex.parse(Data(), mode: .csv).ranges.count, 0)
        let index = try RecordIndex.parse(Data("\n,\n\"\"".utf8), mode: .csv)
        XCTAssertEqual(index.ranges.count, 3)
        XCTAssertEqual(index.cells(at: 0), [""])
        XCTAssertEqual(index.cells(at: 1), ["", ""])
        XCTAssertEqual(index.cells(at: 2), [""])
    }
    func testNDJSONPreservesInvalidRecordAndSkipsBlankLines() throws {
        let index = try RecordIndex.parse(Data("\n{\"a\":[1,2]}\r\n \t\ninvalid\nnull\n".utf8), mode: .ndjson)
        XCTAssertEqual(index.ranges.count, 3)
        XCTAssertEqual(index.preview(at: 1), "invalid")
        XCTAssertThrowsError(try JSONIndex.parse(index.data.subdata(in: index.ranges[1])))
        XCTAssertNoThrow(try JSONIndex.parse(index.data.subdata(in: index.ranges[2])))
    }
    func testMalformedQuotesAndCancellation() {
        for text in ["a,\"unterminated", "a,b\"c", "\"a\"x,b"] {
            XCTAssertThrowsError(try RecordIndex.parse(Data(text.utf8), mode: .csv))
        }
        XCTAssertThrowsError(try RecordIndex.parse(Data("a,b".utf8), mode: .csv, cancelled: { true }))
    }
    func testPagedColumnsAndBoundedCellPreview() throws {
        let text = "abc,\"def\"\"ghi\",last,,"
        let index = try RecordIndex.parse(Data(text.utf8), mode: .csv)
        XCTAssertEqual(index.cells(at: 0, byteLimit: 4, columns: 1..<3), ["def\"…", "last"])
        XCTAssertEqual(index.cells(at: 0, columns: 3..<5), ["", ""])
        XCTAssertEqual(index.cells(at: 0, columns: 8..<9), [])
    }
    func testNDJSONFormatsAllRecordsAsJSONArray() throws {
        let source = "{\"id\":9007199254740993,\"id\":1.2300e+40}\n\n[true,null]\n\"中文\"\n"
        let index = try RecordIndex.parse(Data(source.utf8), mode: .ndjson)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try index.formattedJSON(to: url)
        let text = try String(contentsOf: url)
        XCTAssertTrue(text.contains("9007199254740993")); XCTAssertTrue(text.contains("1.2300e+40"))
        XCTAssertTrue(text.contains("\n    \"id\": "))
        XCTAssertEqual(try JSONIndex.parse(Data(text.utf8)).nodes[0].count, 3)
        XCTAssertEqual(index.data, Data(source.utf8))
    }
    func testNDJSONFormatFailureRemovesPartialOutput() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let index = try RecordIndex.parse(Data("{}\ninvalid\n{}".utf8), mode: .ndjson)
        XCTAssertThrowsError(try index.formattedJSON(to: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("第 2 条记录"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertThrowsError(try index.formattedJSON(to: url, cancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try RecordIndex.parse(Data(), mode: .ndjson).formattedJSON(to: url)
        XCTAssertEqual(try String(contentsOf: url), "[]\n")
        try FileManager.default.removeItem(at: url)
    }
    func testMappedHundredMBRecords() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        let record = Data(("42,\"" + String(repeating: "x", count: 4096) + "\nsecond line\",end\r\n").utf8)
        for _ in 0..<25000 { try handle.write(contentsOf: record) }
        try handle.close()
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        XCTAssertGreaterThan(data.count, 100_000_000)
        let index = try RecordIndex.parse(data, mode: .csv)
        XCTAssertEqual(index.ranges.count, 25000)
        XCTAssertEqual(index.columnCount, 3)
        XCTAssertEqual(index.cells(at: 24999, byteLimit: 10, columns: 1..<3), ["xxxxxxxxxx…", "end"])
    }
}

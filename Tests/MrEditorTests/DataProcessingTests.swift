import XCTest
@testable import MrEditorCore

final class DataProcessingTests: XCTestCase {
    private func output() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func clean(_ input: String, _ options: CSVCleaningOptions) throws -> String {
        let url = output(); defer { try? FileManager.default.removeItem(at: url) }
        _ = try CSVCleaningProcessor.run(data: Data(input.utf8), options: options, output: url)
        return try String(contentsOf: url, encoding: .utf8)
    }
    func testCSVQuotedMultilineTrimDedupAndFill() throws {
        let input = "name,note,n\r\n A ,\" hello,\"\"世界\"\"\r\nnext \",\r\n A ,other,5\r\n B ,ok,2\r\n"
        let options = CSVCleaningOptions(columns: [0], deduplicate: true)
        let index = try RecordIndex.parse(Data(clean(input, options).utf8), mode: .csv)
        XCTAssertEqual(index.ranges.count, 3)
        XCTAssertEqual(index.cells(at: 1), ["A", " hello,\"世界\"\r\nnext ", ""])
        XCTAssertEqual(index.cells(at: 2), ["B", "ok", "2"])
        XCTAssertEqual(try clean("a,b\nx, \n", CSVCleaningOptions(emptyAction: .fill, fillValue: "empty")), "a,b\nx,empty\n")
    }
    func testEmptyRowsDropBeforeConversionAndHeaderUntouched() throws {
        let options = CSVCleaningOptions(emptyAction: .dropRow, conversion: .integer)
        XCTAssertEqual(try clean("a,b\nbad,\n+003,0002\n", options), "a,b\n3,2\n")
    }
    func testUnevenRowsSelectedMissingColumn() throws {
        XCTAssertEqual(try clean("a,b,c\nx\ny,z,1\n", CSVCleaningOptions(columns: [2], emptyAction: .fill, fillValue: "0", conversion: .integer)), "a,b,c\nx,,0\ny,z,1\n")
    }
    func testTSVBooleanAndNoHeader() throws {
        XCTAssertEqual(try clean("yes\tkeep\n0\tstill\n", CSVCleaningOptions(mode: .tsv, header: false, columns: [0], conversion: .boolean)), "true\tkeep\nfalse\tstill\n")
    }
    func testDecimalPrecisionAndIntegerOverflow() throws {
        XCTAssertEqual(try CSVCleaningProcessor.convert("1.2300e2", to: .decimal), "123")
        XCTAssertEqual(try CSVCleaningProcessor.convert("-0.00100", to: .decimal), "-0.001")
        XCTAssertThrowsError(try CSVCleaningProcessor.convert("1234567890123456789012345678901234567890123456789", to: .decimal))
        XCTAssertThrowsError(try CSVCleaningProcessor.convert("9223372036854775808", to: .integer))
        XCTAssertThrowsError(try CSVCleaningProcessor.convert("NaN", to: .decimal))
    }
    func testConversionFailureRemovesPartialFileAndLocatesCell() throws {
        let url = output()
        XCTAssertThrowsError(try CSVCleaningProcessor.run(data: Data("n\n1\nbad\n".utf8), options: CSVCleaningOptions(conversion: .integer), output: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("第 3 条记录，列 1"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testColumnsValidationAndMalformedCSV() throws {
        XCTAssertEqual(try CSVCleaningOptions.parseColumns("1, 3,1"), [0,2])
        XCTAssertNil(try CSVCleaningOptions.parseColumns(" "))
        for value in ["0", "1,", "x", "-1"] { XCTAssertThrowsError(try CSVCleaningOptions.parseColumns(value)) }
        XCTAssertThrowsError(try clean("a,b\n\"unclosed", CSVCleaningOptions()))
        XCTAssertThrowsError(try clean("a,b\nx,y\n", CSVCleaningOptions(columns: [2])))
    }
    func testTimeMillisecondInclusiveBoundariesZoneAndContinuation() throws {
        let input = "preamble\r\n2026-10-02T01:00:00.099Z before\r\n2026-10-02T01:00:00.100Z match\r\n  stack\r\n2026-10-02 09:00:00.200 match2\r\n2026-10-02T01:00:00.201Z after\r\n  excluded\r\n"
        let options = TimeRangeOptions(start: try TimeRangeOptions.parseBoundary("2026-10-02 09:00:00.100", offset: 28800), end: try TimeRangeOptions.parseBoundary("2026-10-02 09:00:00.200", offset: 28800), offset: 28800, year: 2026)
        let url = output(); defer { try? FileManager.default.removeItem(at: url) }
        _ = try TimeRangeProcessor.run(data: Data(input.utf8), options: options, output: url)
        XCTAssertEqual(try String(contentsOf: url), "2026-10-02T01:00:00.100Z match\r\n  stack\r\n2026-10-02 09:00:00.200 match2\r\n")
    }
    func testEpochMillisecondsAndUnsortedRecords() throws {
        let url = output(); defer { try? FileManager.default.removeItem(at: url) }
        let options = TimeRangeOptions(start: Date(timeIntervalSince1970: 1754000000.123), end: Date(timeIntervalSince1970: 1754000000.124), format: .epochMillis, offset: 0, year: 2026, keepContinuation: false)
        _ = try TimeRangeProcessor.run(data: Data("1754000000125 later\n1754000000123 match\nstack\n1754000000124 end".utf8), options: options, output: url)
        XCTAssertEqual(try String(contentsOf: url), "1754000000123 match\n1754000000124 end")
    }
    func testSyslogYearRolloverAndApacheZone() throws {
        let url = output(); defer { try? FileManager.default.removeItem(at: url) }
        var options = TimeRangeOptions(start: try TimeRangeOptions.parseBoundary("2027-01-01 00:00:00", offset: 0), end: nil, format: .syslog, offset: 0, year: 2026)
        _ = try TimeRangeProcessor.run(data: Data("Dec 31 23:59:59 old\nJan  1 00:00:00 new\nstack".utf8), options: options, output: url)
        XCTAssertEqual(try String(contentsOf: url), "Jan  1 00:00:00 new\nstack")
        options = TimeRangeOptions(start: try TimeRangeOptions.parseBoundary("2026-10-02T01:00:00Z", offset: 0), end: nil, format: .apache, offset: 0, year: 2026)
        _ = try TimeRangeProcessor.run(data: Data("ip [02/Oct/2026:09:00:00 +0800] ok".utf8), options: options, output: url)
        XCTAssertEqual(try String(contentsOf: url), "ip [02/Oct/2026:09:00:00 +0800] ok")
    }
    func testExplicitBoundaryZoneOverridesSelectedOffset() throws {
        let utc = try TimeRangeOptions.parseBoundary("2026-10-02T01:00:00.123Z", offset: 28800)
        XCTAssertEqual(utc, try TimeRangeOptions.parseBoundary("2026-10-02T09:00:00.123+08:00", offset: -18000))
        XCTAssertEqual(utc, try TimeRangeOptions.parseBoundary("2026-10-02T01:00:00.123+00:00", offset: 28800))
    }
    func testLongNumericIdentifierDoesNotOverflowTimestampDetection() throws {
        XCTAssertNil(TimestampDetector.detect(sampleLines: ["9999999999999999999999999999999999999999 value"]))
    }
    func testInvalidUTF8FailsWithoutReplacingCharacters() throws {
        let url = output()
        XCTAssertThrowsError(try CSVCleaningProcessor.run(data: Data([97,10,255,10]), options: CSVCleaningOptions(), output: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testBoundsValidationCancellationAndPreviewLimit() throws {
        XCTAssertThrowsError(try TimeRangeOptions.parseBoundary("2026-02-30 00:00:00", offset: 0))
        XCTAssertEqual(try TimeRangeOptions.parseOffset("+08:30"), 30600)
        for offset in ["+14:01", "+08:99", "UTC", "+99:00"] { XCTAssertThrowsError(try TimeRangeOptions.parseOffset(offset)) }
        let url = output(); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try TimeRangeProcessor.run(data: Data("none".utf8), options: TimeRangeOptions(start: Date(), end: Date(timeIntervalSince1970: 0), offset: 0, year: 2026), output: url))
        XCTAssertThrowsError(try CSVCleaningProcessor.run(data: Data("a\n1".utf8), options: CSVCleaningOptions(), output: url, cancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let input = "a\n" + String(repeating: "text\n", count: 20_000)
        let result = try CSVCleaningProcessor.run(data: Data(input.utf8), options: CSVCleaningOptions(), output: url)
        XCTAssertLessThanOrEqual(result.preview.utf8.count, 65_536)
        XCTAssertEqual(try String(contentsOf: url), input)
    }
}

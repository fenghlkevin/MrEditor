import XCTest
@testable import MrEditorCore

final class InvestigationFeaturesTests: XCTestCase {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("textstack-feature-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testFolderRegexSelectiveReplacementBackupAndStaleDetection() throws {
        let root = try temp(), file = root.appendingPathComponent("app.log"), hidden = root.appendingPathComponent(".hidden.log")
        let original = "alpha=12\r\nalpha=34\r\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        try original.write(to: hidden, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.log"), withDestinationURL: file)
        let options = FolderSearchOptions(query: #"(?<=alpha=)(\d+)"#, replacement: "[$1]", regex: true, extensions: "log")
        var result = try FolderSearch.scan(root: root, options: options)
        XCTAssertEqual(result.files.count, 1); XCTAssertEqual(result.hits.map(\.line), [1, 2])
        result.hits[0].selected = false
        let backup = root.appendingPathComponent(".backup")
        let changed = try FolderSearch.replace(result: result, options: options, backup: backup, blockedPaths: [])
        XCTAssertEqual(changed.map { $0.resolvingSymlinksInPath() }, [file.resolvingSymlinksInPath()]); XCTAssertEqual(try String(contentsOf: file), "alpha=12\r\nalpha=[34]\r\n")
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("0-app.log")), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path))
        XCTAssertThrowsError(try FolderSearch.replace(result: result, options: options, backup: root.appendingPathComponent("stale"), blockedPaths: []))
    }
    func testFolderPreservesBOMAndRefusesOpenedFile() throws {
        let root = try temp(), file = root.appendingPathComponent("unicode.txt")
        var original = Data([0xff, 0xfe]); original.append("hello 中文\r\n".data(using: .utf16LittleEndian)!)
        try original.write(to: file)
        let options = FolderSearchOptions(query: "hello", replacement: "hi")
        let result = try FolderSearch.scan(root: root, options: options)
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertThrowsError(try FolderSearch.replace(result: result, options: options, backup: root.appendingPathComponent("blocked"), blockedPaths: [file.path]))
        XCTAssertEqual(try Data(contentsOf: file), original)
        _ = try FolderSearch.replace(result: result, options: options, backup: root.appendingPathComponent(".backup"), blockedPaths: [])
        let changed = try Data(contentsOf: file)
        XCTAssertTrue(changed.starts(with: [0xff, 0xfe]))
        XCTAssertEqual(String(data: changed.dropFirst(2), encoding: .utf16LittleEndian), "hi 中文\r\n")
    }
    func testFolderLiteralDollarReplacementAndZeroWidth() throws {
        let root = try temp(), file = root.appendingPathComponent("file.txt")
        try "a\na".write(to: file, atomically: true, encoding: .utf8)
        let options = FolderSearchOptions(query: "a", replacement: "$1")
        let result = try FolderSearch.scan(root: root, options: options)
        _ = try FolderSearch.replace(result: result, options: options, backup: root.appendingPathComponent(".backup"), blockedPaths: [])
        XCTAssertEqual(try String(contentsOf: file), "$1\n$1")
        let zero = FolderSearchOptions(query: "(?=a)", replacement: "x", regex: true)
        try "ab".write(to: file, atomically: true, encoding: .utf8)
        let zeroResult = try FolderSearch.scan(root: root, options: zero)
        XCTAssertEqual(zeroResult.hits.count, 1)
        _ = try FolderSearch.replace(result: zeroResult, options: zero, backup: root.appendingPathComponent(".backup2"), blockedPaths: [])
        XCTAssertEqual(try String(contentsOf: file), "xab")
    }
    func testLogTimeBucketsTimezoneFieldsAndStackRetention() throws {
        let root = try temp(), output = root.appendingPathComponent("filtered.log")
        let source = "2026-10-03T10:00:00+08:00 ERROR service=api traceId=abc\r\n    at Foo.run(Foo.java:12)\r\n2026-10-03T02:00:30Z WARN service=api traceId=def\r\n2026-10-03T02:01:00Z INFO service=web\r\n"
        var options = LogAnalysisOptions(offset: 28800, year: 2026, field: "service", value: "api")
        let result = try LogAnalysis.run(data: Data(source.utf8), options: options, output: output)
        XCTAssertNil(result.fields["Foo.java"])
        XCTAssertEqual(result.total, 4); XCTAssertEqual(result.dated, 3); XCTAssertEqual(result.matched, 3)
        XCTAssertEqual(result.buckets.count, 1); XCTAssertEqual(result.buckets[0].count, 2); XCTAssertEqual(result.buckets[0].errors, 1); XCTAssertEqual(result.buckets[0].warnings, 1)
        XCTAssertEqual(result.samples.map { $0.0 }, [1,2,3]); XCTAssertTrue(try String(contentsOf: output).contains("Foo.java:12"))
        options.start = try TimeRangeOptions.parseBoundary("2026-10-03 10:00:30", offset: 28800)
        options.end = options.start
        let bounded = try LogAnalysis.run(data: Data(source.utf8), options: options)
        XCTAssertEqual(bounded.samples.map { $0.0 }, [3])
    }
    func testJSONLogAliasesAndSyslogRollover() throws {
        let json = #"{"timestamp":"2026-10-03T10:00:00Z","severity":"warning","trace_id":"a","thread_name":"worker","service.name":"api"}"#
        let fields = LogFields.parse(json).values
        XCTAssertEqual(fields["level"], "WARN"); XCTAssertEqual(fields["traceId"], "a"); XCTAssertEqual(fields["thread"], "worker"); XCTAssertEqual(fields["service"], "api")
        let result = try LogAnalysis.run(data: Data(json.utf8), options: LogAnalysisOptions(offset: 0))
        XCTAssertEqual(result.dated, 1); XCTAssertEqual(result.buckets.first?.warnings, 1)
        let rollover = try LogAnalysis.run(data: Data("Dec 31 23:59:59 INFO ok\nJan  1 00:00:01 ERROR fail".utf8), options: LogAnalysisOptions(offset: 0, year: 2025, format: .syslog))
        XCTAssertEqual(rollover.buckets.count, 2); XCTAssertEqual(rollover.buckets[1].time.timeIntervalSince(rollover.buckets[0].time), 60)
    }
    func testInvalidRangeAndCancellationLeaveNoOutput() throws {
        let root = try temp(), output = root.appendingPathComponent("cancelled.log")
        XCTAssertThrowsError(try LogAnalysis.run(data: Data("2026-10-03 00:00:00 ERROR".utf8), options: LogAnalysisOptions(), output: output, cancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertThrowsError(try FolderSearch.scan(root: root, options: FolderSearchOptions(query: "[", replacement: "", regex: true)))
    }
    func testCharacterInspectionMixedNewlinesInvisibleAndIncompatible() {
        let report = CharacterInspection.report("a\r\nb\nc\r中文\u{200b}\u{202e}", target: .shiftJIS, targetName: "Shift-JIS")
        XCTAssertTrue(report.contains("LF 1 · CRLF 1 · CR 1")); XCTAssertTrue(report.contains("混合换行"))
        XCTAssertTrue(report.contains("U+200B")); XCTAssertTrue(report.contains("U+202E")); XCTAssertTrue(report.contains("无法保存为 Shift-JIS"))
        XCTAssertTrue(report.contains("行 4 · 列 3"))
    }
    func testRemoteRotationCapabilityAndQuoting() {
        let caps = RemoteFile.Capabilities.parse("wc\nhead\ntail\ngrep\ntailRotation\n")
        XCTAssertTrue(caps.hasTailRotation)
        let command = RemoteFile.followCommand("/var/log/a'b.log", bytes: 0, rotation: true)
        XCTAssertTrue(command.contains("-n 0 -F")); XCTAssertTrue(command.contains("'\\''")); XCTAssertTrue(command.contains("kill $p"))
        XCTAssertFalse(RemoteFile.Capabilities.parse("tail\nhead").hasTailRotation)
    }
}

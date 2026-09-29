import XCTest
@testable import MrEditorCore

final class RemoteDirectoryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mreditor-directory-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let directory { try FileManager.default.removeItem(at: directory) } }
    private func run(_ path: String, limit: Int = RemoteDirectory.entryLimit, shell: String = "/bin/sh") throws -> RemoteDirectory.Listing {
        let process = Process(); process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", try RemoteDirectory.command(path: path, limit: limit)]
        process.currentDirectoryURL = directory
        let out = Pipe(); process.standardOutput = out; process.standardError = FileHandle.nullDevice
        try process.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "test-shell", code: Int(process.terminationStatus)) }
        return try RemoteDirectory.parse(data)
    }
    func testListingPreservesSpecialFilenamesAndMetadata() throws {
        let names = ["simple.log", "中文日志.log", "a b\t'\"$` log\nnext.log", "$(touch owned).log", ".hidden.log"]
        for name in names { try Data("abc".utf8).write(to: directory.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("archive"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("broken").path, withDestinationPath: "missing")
        let listing = try run(directory.path, shell: "/bin/zsh")
        XCTAssertEqual(Set(listing.entries.map(\.name)), Set(names + ["archive", "broken"]))
        XCTAssertFalse(listing.truncated)
        for entry in listing.entries where names.contains(entry.name) {
            XCTAssertEqual(entry.kind, .file); XCTAssertEqual(entry.size, 3); XCTAssertNotNil(entry.modified)
        }
        XCTAssertEqual(listing.entries.first { $0.name == "archive" }?.kind, .directory)
        XCTAssertEqual(listing.entries.first { $0.name == "broken" }?.kind, .other)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
    }
    func testEmptyDirectoryWorksWithZshAndMissingDirectoryIsAnError() throws {
        XCTAssertTrue(try run(directory.path, shell: "/bin/zsh").entries.isEmpty)
        XCTAssertThrowsError(try run(directory.appendingPathComponent("missing").path))
    }
    func testDirectoryPathIsShellQuoted() throws {
        let nested = directory.appendingPathComponent("folder ' $(touch owned)\nnext")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data().write(to: nested.appendingPathComponent("empty.log"))
        XCTAssertEqual(try run(nested.path).entries.first?.size, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
    }
    func testTruncationIsExplicitAndMetadataReadsNoFileContents() throws {
        for i in 0..<4 { try Data("PRIVATE CONTENT".utf8).write(to: directory.appendingPathComponent("\(i).log")) }
        let listing = try run(directory.path, limit: 2)
        XCTAssertTrue(listing.truncated); XCTAssertEqual(listing.entries.count, 2)
        XCTAssertFalse(try RemoteDirectory.command(path: directory.path).contains("head"))
    }
    func testRejectsIncompleteOrUnsafeProtocol() throws {
        for response in ["", "MREDIR1\0", "MREDIR1\0F\0a.log\03\00\0", "MREDIR1\0F\0../x\03\00\0E\0\0\0\0", "MOTD\nMREDIR1\0E\0\0\0\0"] {
            XCTAssertThrowsError(try RemoteDirectory.parse(Data(response.utf8)))
        }
        XCTAssertThrowsError(try RemoteDirectory.command(path: "relative/path"))
        XCTAssertThrowsError(try RemoteDirectory.command(path: "/invalid\0path"))
    }
    func testFilteringSortingAndUnsupportedEntries() {
        let folder = RemoteDirectory.Entry(name: "archive", kind: .directory, size: nil, modified: nil)
        let old = RemoteDirectory.Entry(name: "alpha.log", kind: .file, size: 1, modified: Date(timeIntervalSince1970: 1))
        let new = RemoteDirectory.Entry(name: "zeta.log", kind: .file, size: 2, modified: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(RemoteDirectory.sorted([old,new,folder], query: "", byName: false), [folder,new,old])
        XCTAssertEqual(RemoteDirectory.sorted([old,new,folder], query: "", byName: true), [folder,old,new])
        XCTAssertEqual(RemoteDirectory.sorted([old,new,folder], query: "ALPHA", byName: false), [old])
        XCTAssertFalse(RemoteDirectory.Entry(name: "old.log.gz", kind: .file, size: 1, modified: nil).canOpen)
        XCTAssertFalse(folder.canOpen)
    }
    func testLegacyProfilesKeepIdentityAndDeferRemotePathResolution() throws {
        var connection = SSHConnection(); connection.path = "/var/log/app.log"; connection.name = "Production"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(connection)) as? [String: Any])
        object.removeValue(forKey: "pathKind")
        let legacy = try JSONDecoder().decode(SSHConnection.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.pathKind); XCTAssertEqual(legacy.path, connection.path); XCTAssertEqual(legacy.id, connection.id)
        XCTAssertEqual(SSHConnection().pathKind, .directory)
        XCTAssertEqual(RemoteDirectory.parent("/app/logs/file.log"), "/app/logs")
        XCTAssertEqual(RemoteDirectory.parent("/"), "/")
        XCTAssertEqual(RemoteDirectory.child("file.log", in: "/"), "/file.log")
    }
}

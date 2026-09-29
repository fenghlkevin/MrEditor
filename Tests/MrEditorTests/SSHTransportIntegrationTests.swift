import XCTest
@testable import MrEditorCore

/// Opt-in, isolated sshd fixture: no ~/.ssh/config or system sshd required.
final class SSHTransportIntegrationTests: XCTestCase {
    func testEncryptedKeyReadFilterFollowAndHostVerification() throws {
        guard ProcessInfo.processInfo.environment["MREDITOR_SSH_INTEGRATION"] == "1" else {
            throw XCTSkip("Set MREDITOR_SSH_INTEGRATION=1 with the isolated sshd fixture running")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent(".build/ssh-integration")
        let log = fixture.appendingPathComponent("app.log")
        try Data("line one\nERROR sample\nline three\n".utf8).write(to: log)
        var c = SSHConnection()
        c.endpoint = .init(host: "127.0.0.1", port: 22479, user: NSUserName(), authentication: .key,
                           privateKey: fixture.appendingPathComponent("client_key").path)
        c.path = log.path
        var trustPrompts = 0, passwordPrompts = 0
        let transport = try SSHTransport(connection: c, supportDirectory: fixture.appendingPathComponent("support"),
                                         executableURL: root.appendingPathComponent(".build/debug/MrEditor")) { prompt in
            if prompt.contains("(yes/no") { trustPrompts += 1; return "yes" }
            if prompt.contains("passphrase") { passwordPrompts += 1; return "test-passphrase" }
            return nil
        }
        let session = try RemoteSession.connect(using: transport)
        XCTAssertTrue(session.capabilities.canRead)
        XCTAssertEqual(session.read(offset: 0, length: 9), Data("line one\n".utf8))
        XCTAssertEqual(session.searchLines(pattern: "ERROR")?.first?.text, "ERROR sample")
        XCTAssertEqual(session.searchLines(pattern: "error", ignoreCase: true)?.first?.text, "ERROR sample")
        XCTAssertEqual(session.searchLines(pattern: "^ERROR.*sample$", regex: true)?.first?.text, "ERROR sample")
        XCTAssertTrue(session.searchLines(pattern: "error", ignoreCase: false)?.isEmpty == true)
        XCTAssertEqual(session.tailLines().last?.text, "line three")
        XCTAssertEqual(passwordPrompts, 1, "Repeated operations must reuse the authenticated session")
        XCTAssertEqual(trustPrompts, 1)
        let follower = RemoteFollower(session: session)
        let arrived = expectation(description: "live remote line")
        follower.onLines = { lines in if lines.contains("followed line") { arrived.fulfill() } }
        follower.start()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            let handle = try! FileHandle(forWritingTo: log)
            try! handle.seekToEnd(); try! handle.write(contentsOf: Data("followed line\n".utf8)); try! handle.close()
        }
        wait(for: [arrived], timeout: 8)
        follower.stop()
        XCTAssertEqual(passwordPrompts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.appendingPathComponent("support/known_hosts").path),
                       "Session-only trust must not persist host keys")
    }
    func testJumpHostAndChangedHostKey() throws {
        guard ProcessInfo.processInfo.environment["MREDITOR_SSH_INTEGRATION"] == "1" else {
            throw XCTSkip("Requires isolated sshd fixtures")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent(".build/ssh-integration")
        var c = SSHConnection()
        c.endpoint = .init(host: "127.0.0.1", port: 22480, user: NSUserName(), authentication: .key,
                           privateKey: fixture.appendingPathComponent("client_key").path)
        c.jump = c.endpoint; c.jump?.port = 22479
        c.path = fixture.appendingPathComponent("app.log").path
        let support = fixture.appendingPathComponent("jump-support-\(UUID())")
        defer { try? FileManager.default.removeItem(at: support) }
        let transport = try SSHTransport(connection: c, supportDirectory: support,
                                         executableURL: root.appendingPathComponent(".build/debug/MrEditor")) { prompt in
            if prompt.contains("(yes/no") { return "yes" }
            if prompt.contains("passphrase") { return "test-passphrase" }
            return nil
        }
        let session = try RemoteSession.connect(using: transport)
        XCTAssertEqual(session.searchLines(pattern: "ERROR")?.first?.text, "ERROR sample")
        // Persist exactly the explicitly selected host, not both target and jump host.
        transport.rememberedHosts = ["[127.0.0.1]:22480"]
        try transport.persistTrustedHosts()
        let hosts = try String(contentsOf: support.appendingPathComponent("known_hosts"))
        XCTAssertTrue(hosts.contains("[127.0.0.1]:22480"))
        XCTAssertFalse(hosts.contains("[127.0.0.1]:22479"))

        var direct = c; direct.jump = nil; direct.endpoint.port = 22479
        let wrongKey = try String(contentsOf: fixture.appendingPathComponent("client_key.pub"))
        try ("[127.0.0.1]:22479 " + wrongKey).write(to: support.appendingPathComponent("known_hosts"), atomically: true, encoding: .utf8)
        let bad = try SSHTransport(connection: direct, supportDirectory: support,
                                   executableURL: root.appendingPathComponent(".build/debug/MrEditor")) { _ in
            XCTFail("A changed host key must not be offered as a first-time trust prompt")
            return nil
        }
        XCTAssertThrowsError(try RemoteSession.connect(using: bad)) { error in
            guard case RemoteSession.Failure.failed(_, let stderr) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED"))
        }
    }

    func testBrowseChooseRefreshAndLegacyPathsReuseOneConnection() throws {
        guard ProcessInfo.processInfo.environment["MREDITOR_SSH_INTEGRATION"] == "1" else {
            throw XCTSkip("Requires isolated sshd fixtures")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent(".build/ssh-integration")
        let directory = fixture.appendingPathComponent("browse-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("中文 ' current.log")
        try Data("first file\n".utf8).write(to: original)
        let subdirectory = directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: false)
        var c = SSHConnection()
        c.endpoint = .init(host: "127.0.0.1", port: 22479, user: NSUserName(), authentication: .key,
                          privateKey: fixture.appendingPathComponent("client_key").path)
        c.path = directory.path
        var authenticationCount = 0
        let transport = try SSHTransport(connection: c, supportDirectory: fixture.appendingPathComponent("support"),
                                         executableURL: root.appendingPathComponent(".build/debug/MrEditor")) { prompt in
            if prompt.contains("(yes/no") { return "yes" }
            if prompt.contains("passphrase") { authenticationCount += 1; return "test-passphrase" }
            return nil
        }
        let browser = try RemoteSession.connect(using: transport, requireFile: false)
        let location = try browser.browserLocation(path: c.path, legacy: false)
        XCTAssertEqual(location.directory, directory.path)
        XCTAssertNil(location.selectedName)
        XCTAssertEqual(Set(try browser.listDirectory(c.path).entries.map(\.name)), [original.lastPathComponent, "archive"])
        XCTAssertTrue(try browser.listDirectory(subdirectory.path).entries.isEmpty)
        let oldProfile = try browser.browserLocation(path: original.path, legacy: true)
        XCTAssertEqual(oldProfile.directory, directory.path)
        XCTAssertEqual(oldProfile.selectedName, original.lastPathComponent)
        let selected = try browser.selectingFile(original.path)
        XCTAssertTrue(selected.transport === browser.transport)
        XCTAssertEqual(selected.tailLines().last?.text, "first file")

        try FileManager.default.removeItem(at: original)
        let replacement = directory.appendingPathComponent("rotated-2026-09-28.log")
        try Data("second file\n".utf8).write(to: replacement)
        XCTAssertThrowsError(try browser.selectingFile(original.path))
        let migrated = try browser.browserLocation(path: original.path, legacy: true)
        XCTAssertEqual(migrated.directory, directory.path); XCTAssertNil(migrated.selectedName)
        XCTAssertTrue(try browser.listDirectory(directory.path).entries.contains { $0.name == replacement.lastPathComponent })
        XCTAssertEqual(try browser.selectingFile(replacement.path).tailLines().last?.text, "second file")
        let missingDirectory = directory.appendingPathComponent("does-not-exist").path
        XCTAssertEqual(try browser.browserLocation(path: missingDirectory, legacy: false).directory, missingDirectory)
        XCTAssertThrowsError(try browser.listDirectory(missingDirectory))
        XCTAssertEqual(authenticationCount, 1)
        XCTAssertEqual(transport.connection.path, directory.path, "Choosing a file must not bind the profile to its filename")
    }

}

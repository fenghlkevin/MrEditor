import XCTest
@testable import MrEditorCore

final class SSHConnectionTests: XCTestCase {
    private func connection() -> SSHConnection {
        var c = SSHConnection()
        c.endpoint.host = "example.test"; c.endpoint.user = "deploy"; c.path = "/var/log/app.log"
        return c
    }
    func testRejectsConfigInjectionAndInvalidPorts() throws {
        for host in ["-oProxyCommand=whoami", "server\nProxyCommand evil", "host name", "a\"b", "a%b"] {
            var c = connection(); c.endpoint.host = host
            XCTAssertThrowsError(try c.validate())
        }
        for port in [0, -1, 65536] {
            var c = connection(); c.endpoint.port = port
            XCTAssertThrowsError(try c.validate())
        }
        var c = connection(); c.endpoint.host = "2001:db8::1"; c.endpoint.port = 2222
        XCTAssertNoThrow(try c.validate())
    }
    func testStoreRoundTripUpdateAndDuplicateWithoutSecrets() throws {
        let suite = "MrEditor.SSH.Tests.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SSHConnectionStore(defaults: defaults)
        var c = connection(); c.name = "Test"
        XCTAssertTrue(store.load().isEmpty)
        // A temporary configuration alone has no persistence side effect.
        try c.validate(); XCTAssertTrue(store.load().isEmpty)
        try store.save(c); XCTAssertEqual(store.load(), [c])
        c.path = "/new.log"; try store.save(c); XCTAssertEqual(store.load(), [c])
        var duplicate = c; duplicate.id = UUID(); try store.save(duplicate)
        XCTAssertEqual(store.load().count, 2)
        try store.delete(duplicate.id)
        XCTAssertEqual(store.load(), [c])
        let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertFalse(json.contains("target")); XCTAssertFalse(json.contains("passphrase"))
    }
    func testGeneratedConfigIsIndependentAndSupportsJumpHost() throws {
        var c = connection(); c.jump = .init(host: "jump.test", port: 2200, user: "gateway", authentication: .agent)
        let config = SSHTransport.configuration(c, knownHosts: "/tmp/test/known_hosts")
        XCTAssertTrue(config.contains("ProxyJump mreditor-jump"))
        XCTAssertTrue(config.contains("GlobalKnownHostsFile /dev/null"))
        XCTAssertTrue(config.contains("StrictHostKeyChecking ask"))
        XCTAssertTrue(config.contains("ForwardAgent no"))
        XCTAssertFalse(config.contains("StrictHostKeyChecking no"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ssh-config-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.write(to: url, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-F", url.path, "-G", "mreditor-target"]
        let output = Pipe(); p.standardOutput = output; p.standardError = FileHandle.nullDevice
        try p.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        let resolved = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(resolved.contains("hostname example.test\n"))
        XCTAssertTrue(resolved.contains("user deploy\n"))
        XCTAssertTrue(resolved.contains("proxyjump mreditor-jump\n"))
    }
    func testAskpassRoundTripKeepsSecretOutOfDiskAndEnvironment() throws {
        let dir = URL(fileURLWithPath: "/tmp/mre-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = "secret-\(UUID())"
        let server = try SSHAskPass(directory: dir) { prompt in prompt == "test-prompt" ? secret : nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/MrEditor")
        process.arguments = ["--mreditor-ssh-askpass", "test-prompt"]
        process.environment = ["MREDITOR_ASKPASS_SOCKET": server.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), secret)
        XCTAssertFalse(process.environment!.values.contains(secret))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["ask.sock"])
        withExtendedLifetime(server) {}
    }
}

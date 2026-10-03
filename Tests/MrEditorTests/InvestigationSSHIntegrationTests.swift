import AppKit
import XCTest
@testable import MrEditorCore

@MainActor
final class InvestigationSSHIntegrationTests: XCTestCase {
    func testRotationFollowingAndReaderReconnect() async throws {
        guard ProcessInfo.processInfo.environment["MREDITOR_SSH_INTEGRATION"] == "1" else { throw XCTSkip("Requires isolated project sshd fixture") }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent(".build/ssh-integration")
        let directory = fixture.appendingPathComponent("rotation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("app.log"), rotated = directory.appendingPathComponent("app.log.1")
        try Data("original\n".utf8).write(to: file)
        var connection = SSHConnection()
        connection.endpoint = .init(host: "127.0.0.1", port: 22479, user: NSUserName(), authentication: .key, privateKey: fixture.appendingPathComponent("client_key").path)
        connection.path = file.path
        let transport = try SSHTransport(connection: connection, supportDirectory: directory.appendingPathComponent("support"), executableURL: root.appendingPathComponent(".build/debug/TextStack")) { prompt in
            if prompt.contains("(yes/no") { return "yes" }; if prompt.contains("passphrase") { return "test-passphrase" }; return nil
        }
        // SSH commands must stay off main, including in integration verification.
        let session = try await Task.detached { try RemoteSession.connect(using: transport) }.value
        XCTAssertTrue(session.capabilities.hasTailRotation)
        let follower = RemoteFollower(session: session)
        let arrived = expectation(description: "rotated file content arrived")
        var fulfilled = false
        follower.onLines = { lines in if lines.contains("after rotation"), !fulfilled { fulfilled = true; arrived.fulfill() } }
        follower.start()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try FileManager.default.moveItem(at: file, to: rotated)
        try Data("after rotation\n".utf8).write(to: file)
        await fulfillment(of: [arrived], timeout: 8)
        follower.stop()
        let reader = RemoteWindowController(); reader.window?.isReleasedWhenClosed = false; reader.showWindow(nil); reader.open(session: session, follow: false)
        defer { reader.shutdown(); reader.close() }
        try await waitUntil { reader.loadedLogText.contains("after rotation") }
        try Data("after refresh\n".utf8).write(to: file)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let button = try XCTUnwrap(descendants(reader.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "重连 / 刷新" })
        button.performClick(nil)
        try await waitUntil { reader.currentSession !== session && reader.loadedLogText.contains("after refresh") }
        XCTAssertTrue(reader.currentSession?.transport === transport)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }
        XCTFail("SSH reader operation timed out"); throw ProcessingError(message: "SSH reader timed out")
    }
}

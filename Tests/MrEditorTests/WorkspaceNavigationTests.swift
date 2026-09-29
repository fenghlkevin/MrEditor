import XCTest
@testable import MrEditorCore

final class WorkspaceNavigationTests: XCTestCase {
    func testFilteringPreservesOriginalDocumentIndices() {
        let server = SSHConnection()
        let documents = [WorkspaceDocument(index: 0, name: "a", dirty: false, connection: server),
                         WorkspaceDocument(index: 1, name: "b", dirty: true, connection: nil),
                         WorkspaceDocument(index: 2, name: "c", dirty: false, connection: server),
                         WorkspaceDocument(index: 3, name: "d", dirty: false, connection: nil)]
        XCTAssertEqual(WorkspaceNavigation.local(documents).map(\.index), [1, 3])
        XCTAssertTrue(WorkspaceNavigation.local(documents)[0].dirty)
        XCTAssertEqual(WorkspaceNavigation.servers(saved: [server], documents: documents)[0].documents.map(\.index), [0, 2])
    }
    func testSameHostProfilesStaySeparateAndSavedMetadataWins() {
        var first = SSHConnection(); first.name = "old name"; first.endpoint.host = "host"
        var second = first; second.id = UUID(); second.name = "second"
        var updated = first; updated.name = "renamed"
        let documents = [WorkspaceDocument(index: 3, name: "app.log", dirty: false, connection: first),
                         WorkspaceDocument(index: 7, name: "app.log", dirty: false, connection: second)]
        let groups = WorkspaceNavigation.servers(saved: [second, updated], documents: documents)
        XCTAssertEqual(groups.map { $0.connection.name }, ["second", "renamed"])
        XCTAssertEqual(groups.map { $0.documents.map(\.index) }, [[7], [3]])
        XCTAssertTrue(groups.allSatisfy(\.saved))
    }
    func testTemporaryAndDeletedProfilesRemainReachableUntilFilesClose() {
        let temporary = SSHConnection(), saved = SSHConnection()
        let document = WorkspaceDocument(index: 4, name: "log", dirty: false, connection: temporary)
        let groups = WorkspaceNavigation.servers(saved: [saved], documents: [document, document])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[0].documents.isEmpty)
        XCTAssertFalse(groups[1].saved)
        XCTAssertEqual(groups[1].connection.id, temporary.id)
        XCTAssertEqual(WorkspaceNavigation.servers(saved: [saved], documents: []).count, 1)
    }
}

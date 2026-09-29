import Foundation

/// Preserve original document indices while filtering local and per-server navigation.
struct WorkspaceDocument {
    let index: Int
    let name: String
    let dirty: Bool
    let connection: SSHConnection?
}
struct WorkspaceServer {
    let connection: SSHConnection
    let documents: [WorkspaceDocument]
    let saved: Bool
}
enum WorkspaceNavigation {
    static func local(_ documents: [WorkspaceDocument]) -> [WorkspaceDocument] {
        documents.filter { $0.connection == nil }
    }
    static func servers(saved: [SSHConnection], documents: [WorkspaceDocument]) -> [WorkspaceServer] {
        var records = saved
        for document in documents {
            if let connection = document.connection, !records.contains(where: { $0.id == connection.id }) {
                records.append(connection)
            }
        }
        return records.map { connection in
            WorkspaceServer(connection: connection,
                            documents: documents.filter { $0.connection?.id == connection.id },
                            saved: saved.contains { $0.id == connection.id })
        }
    }
}

import Foundation
import Security

struct SSHConnection: Codable, Equatable, Identifiable {
    enum Authentication: String, Codable, CaseIterable { case password, key, agent }
    struct Endpoint: Codable, Equatable {
        var host = ""
        var port = 22
        var user = ""
        var authentication: Authentication = .password
        var privateKey = ""

        func validate() throws {
            let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            guard !host.isEmpty, !host.hasPrefix("-"), host.rangeOfCharacter(from: forbidden) == nil,
                  !host.contains("/"), !host.contains("\""), !host.contains("%"),
                  !user.isEmpty, !user.hasPrefix("-"), user.rangeOfCharacter(from: forbidden) == nil,
                  !user.contains("\""), !user.contains("%"), (1...65535).contains(port) else {
                throw SSHConnectionError.invalidEndpoint
            }
            if authentication == .key {
                guard privateKey.hasPrefix("/"), !privateKey.contains("\n"), !privateKey.contains("\r"),
                      !privateKey.contains("%"), FileManager.default.isReadableFile(atPath: privateKey) else {
                    throw SSHConnectionError.invalidKey
                }
            }
        }
    }
    var id = UUID()
    var name = ""
    var endpoint = Endpoint()
    enum PathKind: String, Codable { case directory }
    var path = ""
    // Missing in v1 profiles: resolve the old file-or-directory path on the server.
    var pathKind: PathKind? = .directory
    var follow = true
    var jump: Endpoint?
    var rememberCredentials = false

    func validate() throws {
        try endpoint.validate()
        try jump?.validate()
        guard path.hasPrefix("/"), !path.contains("\0"), !path.contains("\n"), !path.contains("\r") else {
            throw SSHConnectionError.invalidPath
        }
    }
}

enum SSHConnectionError: LocalizedError {
    case invalidEndpoint, invalidKey, invalidPath, keychain
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return L("ssh.invalidEndpoint")
        case .invalidKey: return L("ssh.invalidKey")
        case .invalidPath: return L("ssh.invalidPath")
        case .keychain: return L("ssh.keychainError")
        }
    }
}

/// Only non-secret settings are Codable. Temporary connections never enter this store.
final class SSHConnectionStore {
    private let defaults: UserDefaults
    private let key = "ssh.savedConnections.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> [SSHConnection] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SSHConnection].self, from: data)) ?? []
    }
    func save(_ connection: SSHConnection) throws {
        var list = load()
        if let index = list.firstIndex(where: { $0.id == connection.id }) { list[index] = connection }
        else { list.append(connection) }
        defaults.set(try JSONEncoder().encode(list), forKey: key)
        NotificationCenter.default.post(name: .sshConnectionsChanged, object: nil)
    }
    func delete(_ id: UUID) throws {
        try SSHCredentials.delete(id)
        defaults.set(try JSONEncoder().encode(load().filter { $0.id != id }), forKey: key)
        NotificationCenter.default.post(name: .sshConnectionsChanged, object: nil)
    }
}

struct SSHCredentials: Codable {
    var target = ""
    var jump = ""
    private static let service = "MrEditor.SSH"
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    static func load(_ id: UUID) -> SSHCredentials {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(_ id: UUID) throws {
        let data = try JSONEncoder().encode(self), q = Self.query(id)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SSHConnectionError.keychain }
    }
    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SSHConnectionError.keychain }
    }
}

extension Notification.Name { static let sshConnectionsChanged = Notification.Name("MrEditor.sshConnectionsChanged") }

import AppKit

/// Lifetime follows the SSH session, not the connection-management window.
final class SSHAuthentication {
    let connection: SSHConnection
    var credentials: SSHCredentials
    weak var transport: SSHTransport?
    var cancelled = false
    private var suppliedPrompts = Set<String>()
    init(connection: SSHConnection, credentials: SSHCredentials) {
        self.connection = connection
        self.credentials = credentials
    }
    /// Runs on main. OpenSSH supplies the actual fingerprint and refuses changed keys itself.
    func answer(_ prompt: String) -> String? {
        guard !cancelled else { return nil }
        let c = connection
        let trust = prompt.contains("(yes/no") || prompt.contains("Are you sure you want to continue connecting")
        if trust {
            let alert = NSAlert(); alert.messageText = L("ssh.trustTitle"); alert.informativeText = prompt
            let remember = NSButton(checkboxWithTitle: L("ssh.rememberHost"), target: nil, action: nil)
            remember.frame = NSRect(x: 0, y: 0, width: 380, height: 24); alert.accessoryView = remember
            alert.addButton(withTitle: L("ssh.trust")); alert.addButton(withTitle: L("ssh.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { cancelled = true; return nil }
            if remember.state == .on {
                for endpoint in [c.endpoint, c.jump].compactMap({ $0 }) {
                    let identity = endpoint.port == 22 ? endpoint.host : "[\(endpoint.host)]:\(endpoint.port)"
                    if prompt.contains("'\(identity) ") || prompt.contains("'\(identity)'") {
                        transport?.rememberedHosts.insert(identity)
                    }
                }
            }
            return "yes"
        }
        let isJump = c.jump.map { j in
            prompt.contains("\(j.user)@\(j.host)") || (!j.privateKey.isEmpty && prompt.contains(j.privateKey))
        } ?? false
        let endpoint = isJump ? (c.jump ?? c.endpoint) : c.endpoint
        let ambiguous = c.jump.map { $0.host == c.endpoint.host && $0.user == c.endpoint.user && $0.privateKey == c.endpoint.privateKey } ?? false
        let isCredential = !ambiguous && ((prompt.contains("\(endpoint.user)@\(endpoint.host)") && prompt.lowercased().contains("password"))
            || (!endpoint.privateKey.isEmpty && prompt.contains(endpoint.privateKey) && prompt.lowercased().contains("passphrase")))
        let value = isCredential ? (isJump ? credentials.jump : credentials.target) : ""
        if !value.isEmpty, !suppliedPrompts.contains(prompt) {
            suppliedPrompts.insert(prompt)
            return value
        }
        let alert = NSAlert(); alert.messageText = L("ssh.credentialsTitle"); alert.informativeText = prompt
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.addButton(withTitle: L("ssh.connect")); alert.addButton(withTitle: L("ssh.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { cancelled = true; return nil }
        let response = field.stringValue
        if isCredential {
            if isJump { credentials.jump = response } else { credentials.target = response }
        }
        suppliedPrompts.insert(prompt)
        return response
    }
}

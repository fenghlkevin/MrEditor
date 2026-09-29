import Foundation

final class SSHTransport {
    let connection: SSHConnection
    let directory: URL
    private let askPass: SSHAskPass
    private let config: URL
    private let helper: URL
    private let knownHosts: URL
    private let permanentHosts: URL
    var rememberedHosts = Set<String>()
    private static let hostsLock = NSLock()

    init(connection: SSHConnection, supportDirectory: URL? = nil, executableURL: URL? = nil, answer: @escaping (String) -> String?) throws {
        try connection.validate()
        self.connection = connection
        // Short private directory keeps Unix socket paths within macOS's 104-byte limit.
        directory = URL(fileURLWithPath: "/tmp/mre-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        config = directory.appendingPathComponent("config")
        helper = directory.appendingPathComponent("askpass")
        knownHosts = directory.appendingPathComponent("known_hosts")
        let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true).appendingPathComponent("MrEditor/SSH")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        permanentHosts = support.appendingPathComponent("known_hosts")
        do {
            try (FileManager.default.fileExists(atPath: permanentHosts.path) ? Data(contentsOf: permanentHosts) : Data())
                .write(to: knownHosts, options: .atomic)
            askPass = try SSHAskPass(directory: directory, answer: answer)
            let executable = executableURL?.path ?? Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
            try "#!/bin/sh\nexec \(RemoteFile.shellQuote(executable)) --mreditor-ssh-askpass \"$@\"\n"
                .write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            try Self.configuration(connection, knownHosts: knownHosts.path)
                .write(to: config, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        let directory = directory, config = config
        DispatchQueue.global().async {
            for host in ["mreditor-target", "mreditor-jump"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = ["-F", config.path, "-O", "exit", host]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                if (try? process.run()) != nil { process.waitUntilExit() }
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    static func configuration(_ c: SSHConnection, knownHosts: String) -> String {
        func endpoint(_ e: SSHConnection.Endpoint, alias: String) -> String {
            var lines = ["Host \(alias)", " HostName \(quote(e.host))", " Port \(e.port)", " User \(quote(e.user))"]
            switch e.authentication {
            case .password:
                lines += [" PreferredAuthentications password", " PubkeyAuthentication no", " IdentityAgent none"]
            case .key:
                lines += [" PreferredAuthentications publickey", " IdentitiesOnly yes", " IdentityAgent none", " IdentityFile \(quote(e.privateKey))"]
            case .agent:
                lines += [" PreferredAuthentications publickey", " IdentityFile none"]
            }
            return lines.joined(separator: "\n")
        }
        var text = endpoint(c.endpoint, alias: "mreditor-target")
        if let jump = c.jump {
            text += "\n ProxyJump mreditor-jump\n" + endpoint(jump, alias: "mreditor-jump")
        }
        text += """

        Host *
         UserKnownHostsFile \(quote(knownHosts))
         GlobalKnownHostsFile /dev/null
         StrictHostKeyChecking ask
         UpdateHostKeys no
         HashKnownHosts no
         KbdInteractiveAuthentication no
         CheckHostIP no
         ConnectTimeout 20
         ConnectionAttempts 1
         NumberOfPasswordPrompts 3
         ServerAliveInterval 15
         ServerAliveCountMax 2
         ControlMaster auto
         ControlPersist 60
         ControlPath \(quote(URL(fileURLWithPath: knownHosts).deletingLastPathComponent().appendingPathComponent("c-%n").path))
         ForwardAgent no
         ClearAllForwardings yes
         RequestTTY no
         EscapeChar none

        """
        return text
    }
    func configure(_ process: Process, command: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-F", config.path, "-T", "mreditor-target", command]
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = helper.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = ":0"
        environment["MREDITOR_ASKPASS_SOCKET"] = askPass.path
        environment["LC_ALL"] = "C"
        process.environment = environment
    }
    /// Merge trusted host keys without overwriting keys approved by another window.
    func persistTrustedHosts() throws {
        guard !rememberedHosts.isEmpty else { return }
        Self.hostsLock.lock(); defer { Self.hostsLock.unlock() }
        let incoming = try String(contentsOf: knownHosts, encoding: .utf8)
        let existing = (try? String(contentsOf: permanentHosts, encoding: .utf8)) ?? ""
        var lines = existing.split(separator: "\n").map(String.init)
        for line in incoming.split(separator: "\n").map(String.init) where !lines.contains(line) {
            let hosts = line.split(separator: " ").first?.split(separator: ",").map(String.init) ?? []
            if hosts.contains(where: rememberedHosts.contains) { lines.append(line) }
        }
        try (lines.joined(separator: "\n") + "\n").write(to: permanentHosts, atomically: true, encoding: .utf8)
    }
}

import Foundation
import Darwin

/// SSH asks the running app through a private Unix socket. Secrets never enter arguments,
/// environment variables, generated scripts, or temporary files.
final class SSHAskPass {
    private let socketFD: Int32
    let path: String
    private let answer: (String) -> String?

    init(directory: URL, answer: @escaping (String) -> String?) throws {
        path = directory.appendingPathComponent("ask.sock").path
        self.answer = answer
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.EIO) }
        let result = Self.withAddress(path) { Darwin.bind(socketFD, $0, $1) }
        guard result == 0, listen(socketFD, 8) == 0 else {
            Darwin.close(socketFD)
            throw POSIXError(.EIO)
        }
        let fd = socketFD
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                let handle = FileHandle(fileDescriptor: client, closeOnDealloc: true)
                guard let data = try? handle.readToEnd(), let prompt = String(data: data, encoding: .utf8),
                      let callback = self?.answer else { try? handle.close(); continue }
                if let response = callback(prompt) { try? handle.write(contentsOf: Data(response.utf8)) }
                try? handle.close()
            }
        }
    }
    deinit {
        shutdown(socketFD, SHUT_RDWR)
        Darwin.close(socketFD)
        unlink(path)
    }
    static func withAddress<T>(_ path: String, _ operation: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            let pathBytes = Array(path.utf8) + [0]
            precondition(pathBytes.count <= bytes.count)
            bytes.copyBytes(from: pathBytes)
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { operation($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    static func runHelperIfNeeded() {
        guard CommandLine.arguments.dropFirst().first == "--mreditor-ssh-askpass" else { return }
        guard let path = ProcessInfo.processInfo.environment["MREDITOR_ASKPASS_SOCKET"], path.utf8.count < 104 else { exit(1) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withAddress(path, { Darwin.connect(fd, $0, $1) }) == 0 else { exit(1) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data((CommandLine.arguments.dropFirst(2).first ?? "").utf8))
            shutdown(fd, SHUT_WR)
            let data = try handle.readToEnd() ?? Data()
            guard !data.isEmpty else { exit(1) }
            try FileHandle.standardOutput.write(contentsOf: data)
            exit(0)
        } catch { exit(1) }
    }
}

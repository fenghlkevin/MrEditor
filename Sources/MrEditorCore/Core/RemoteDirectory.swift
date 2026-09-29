import Foundation

/// NUL-delimited records keep spaces, quotes, tabs and newlines in remote filenames intact.
/// Only directory metadata is transferred; file contents are read after an explicit selection.
enum RemoteDirectory {
    static let entryLimit = 10_000
    enum Kind: String { case directory = "D", file = "F", other = "O" }
    struct Entry: Equatable {
        let name: String
        let kind: Kind
        let size: Int64?
        let modified: Date?
        var isCompressed: Bool {
            kind == .file && ["gz", "bz2", "xz", "zip", "zst", "7z"].contains((name as NSString).pathExtension.lowercased())
        }
        var canOpen: Bool { kind == .file && !isCompressed }
    }
    struct Listing {
        let entries: [Entry]
        let truncated: Bool
    }
    enum ListingError: LocalizedError {
        case invalidPath, invalidResponse
        var errorDescription: String? { L(self == .invalidPath ? "ssh.directoryInvalid" : "ssh.directoryResponse") }
    }
    static func validate(_ path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw ListingError.invalidPath }
    }
    /// Do not normalize `..` on the client: a remote symlink can change its meaning.
    static func parent(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
    }
    static func child(_ name: String, in directory: String) -> String {
        (directory == "/" ? "" : directory.hasSuffix("/") ? String(directory.dropLast()) : directory) + "/" + name
    }
    static func sorted(_ entries: [Entry], query: String, byName: Bool) -> [Entry] {
        entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            if (a.kind == .directory) != (b.kind == .directory) { return a.kind == .directory }
            if !byName, a.kind != .directory, a.modified != b.modified {
                return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    static func command(path: String, limit: Int = entryLimit) throws -> String {
        try validate(path)
        let inaccessible = RemoteFile.shellQuote(L("ssh.directoryUnavailable", path))
        let script = """
        dir=\(RemoteFile.shellQuote(path))
        if ! test -d "$dir" || ! test -r "$dir" || ! test -x "$dir"; then
          printf '%s\\n' \(inaccessible) >&2; exit 1
        fi
        if stat -L -c '%s %Y' "$dir" >/dev/null 2>&1; then style=gnu
        elif stat -L -f '%z %m' "$dir" >/dev/null 2>&1; then style=bsd
        else style=none; fi
        printf 'MREDIR1\\000'
        count=0
        for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
          test -e "$entry" || test -L "$entry" || continue
          if test "$count" -ge \(max(1, limit)); then printf 'L\\000\\000\\000\\000'; exit 0; fi
          name=${entry##*/}
          if test -d "$entry"; then kind=D
          elif test -f "$entry"; then kind=F
          else kind=O; fi
          size=; modified=
          if test "$style" = gnu; then meta=$(stat -L -c '%s %Y' "$entry" 2>/dev/null) || meta=
          elif test "$style" = bsd; then meta=$(stat -L -f '%z %m' "$entry" 2>/dev/null) || meta=
          else meta=; fi
          if test -n "$meta"; then size=${meta%% *}; modified=${meta#* }; fi
          printf '%s\\000%s\\000%s\\000%s\\000' "$kind" "$name" "$size" "$modified"
          count=$((count + 1))
        done
        printf 'E\\000\\000\\000\\000'
        """
        // The login shell may be zsh with NOMATCH: evaluate glob loops in POSIX sh.
        return "/bin/sh -c " + RemoteFile.shellQuote(script)
    }
    static func parse(_ data: Data) throws -> Listing {
        var parts = data.split(separator: 0, omittingEmptySubsequences: false)
        guard parts.first == Data("MREDIR1".utf8), parts.last?.isEmpty == true else { throw ListingError.invalidResponse }
        parts.removeFirst(); parts.removeLast()
        guard parts.count >= 4, parts.count % 4 == 0 else { throw ListingError.invalidResponse }
        var entries: [Entry] = []
        var names = Set<String>()
        for index in stride(from: 0, to: parts.count, by: 4) {
            let type = String(decoding: parts[index], as: UTF8.self)
            if type == "E" || type == "L" {
                guard index == parts.count - 4, parts[index+1].isEmpty, parts[index+2].isEmpty, parts[index+3].isEmpty else {
                    throw ListingError.invalidResponse
                }
                return Listing(entries: entries, truncated: type == "L")
            }
            guard let kind = Kind(rawValue: type), let name = String(data: parts[index+1], encoding: .utf8),
                  !name.isEmpty, name != ".", name != "..", !name.contains("/"), names.insert(name).inserted else {
                throw ListingError.invalidResponse
            }
            let size = Int64(String(decoding: parts[index+2], as: UTF8.self))
            let seconds = Double(String(decoding: parts[index+3], as: UTF8.self))
            entries.append(Entry(name: name, kind: kind, size: size.flatMap { $0 >= 0 ? $0 : nil },
                                 modified: seconds.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }))
        }
        throw ListingError.invalidResponse // Never present a partial transfer as a complete directory.
    }
}

extension RemoteSession {
    struct BrowserLocation {
        let directory: String
        let selectedName: String?
    }
    func browserLocation(path: String, legacy: Bool) throws -> BrowserLocation {
        try RemoteDirectory.validate(path)
        let p = RemoteFile.shellQuote(path)
        let data = try Self.run(host: target.host,
            command: "if test -d \(p); then printf D; elif test -f \(p); then printf F; else printf M; fi",
            timeout: 30, transport: transport)
        let kind = String(decoding: data, as: UTF8.self)
        guard ["D", "F", "M"].contains(kind) else { throw RemoteDirectory.ListingError.invalidResponse }
        if kind == "F" || (kind == "M" && legacy) {
            return BrowserLocation(directory: RemoteDirectory.parent(path), selectedName: kind == "F" ? path.split(separator: "/").last.map(String.init) : nil)
        }
        return BrowserLocation(directory: path, selectedName: nil)
    }
    func listDirectory(_ path: String) throws -> RemoteDirectory.Listing {
        let data = try Self.run(host: target.host, command: RemoteDirectory.command(path: path), timeout: 60, transport: transport)
        return try RemoteDirectory.parse(data)
    }
}

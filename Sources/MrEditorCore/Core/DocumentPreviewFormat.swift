import Foundation

/// Shared selection for the editor and Finder extension. Unknown binary types
/// never opt into the text renderer.
enum DocumentPreviewFormat {
    static let syntax: [String: String] = [
        "js":"javascript", "jsx":"javascript", "mjs":"javascript", "ts":"typescript", "tsx":"typescript",
        "py":"python", "sh":"bash", "bash":"bash", "zsh":"bash", "fish":"shell", "sql":"sql",
        "swift":"swift", "java":"java", "kt":"kotlin", "kts":"kotlin", "c":"c", "h":"c", "cpp":"cpp", "hpp":"cpp", "cc":"cpp",
        "cs":"csharp", "go":"go", "rs":"rust", "rb":"ruby", "php":"php", "lua":"lua", "pl":"perl", "r":"r", "dart":"dart",
        "css":"css", "scss":"scss", "less":"less", "xml":"xml", "plist":"xml", "toml":"ini", "ini":"ini", "conf":"ini", "cfg":"ini", "properties":"properties", "env":"ini",
        "log":"log", "out":"log", "txt":"text", "diff":"diff", "patch":"diff", "vue":"xml", "svelte":"xml",
    ]
    static func kind(for url: URL?) -> String? {
        guard let url else { return nil }
        let ext = url.pathExtension.lowercased(), name = url.lastPathComponent.lowercased()
        switch ext {
        case "md", "markdown": return "markdown"
        case "json", "jsonl", "ndjson": return ext == "json" ? "json" : "code"
        case "yaml", "yml": return "yaml"
        case "csv": return "csv"
        case "tsv", "tab": return "tsv"
        case "mmd", "mermaid": return "mermaid"
        case "html", "htm": return "html"
        case "svg": return "svg"
        default: return syntax[ext] != nil || ["dockerfile", "makefile", ".gitignore", ".env"].contains(name) ? "code" : nil
        }
    }
    static func language(for url: URL?) -> String {
        guard let url else { return "text" }
        switch url.lastPathComponent.lowercased() {
        case "dockerfile": return "dockerfile"
        case "makefile": return "makefile"
        case ".env": return "ini"
        default: break
        }
        let ext = url.pathExtension.lowercased()
        if ["jsonl", "ndjson"].contains(ext) { return "json" }
        return syntax[ext] ?? (["json", "yaml", "yml", "html", "htm", "svg"].contains(ext) ? (["html", "htm", "svg"].contains(ext) ? "xml" : (ext == "yml" ? "yaml" : ext)) : "markdown")
    }
}

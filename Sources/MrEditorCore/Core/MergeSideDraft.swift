import Foundation

/// A tagged envelope preserves empty edited results without treating ordinary drafts as metadata.
struct MergeSideDraft: Codable {
    let text: String
    let side: String
    var displayName: String? = nil
    private static let prefix = "TextStack Merge Draft v1\n"
    var serialized: String {
        Self.prefix + String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }
    static func decode(_ value: String) -> MergeSideDraft? {
        guard value.hasPrefix(prefix) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(value.dropFirst(prefix.count).utf8))
    }
}

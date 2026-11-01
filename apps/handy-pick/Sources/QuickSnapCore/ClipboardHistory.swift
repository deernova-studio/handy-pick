import Foundation

/// Session-only storage. Never persists clipboard data to disk.
public struct ClipboardHistory {
    public enum Content: Equatable {
        case text(String)
        case image(Data, type: String)
        public var byteCount: Int {
            switch self { case .text(let text): return text.utf8.count; case .image(let data, _): return data.count }
        }
    }
    public struct Entry: Identifiable, Equatable {
        public let id: UUID
        public let content: Content
    }
    public private(set) var entries: [Entry] = []
    public private(set) var byteCount = 0
    public let maximumBytes: Int
    private let maximumCount: Int
    public init(maximumCount: Int = 60, maximumBytes: Int = 64 * 1024 * 1024) {
        self.maximumCount = max(0, maximumCount); self.maximumBytes = max(0, maximumBytes)
    }
    @discardableResult public mutating func insert(_ content: Content) -> Bool {
        guard content.byteCount > 0, content.byteCount <= maximumBytes, maximumCount > 0 else { return false }
        if entries.first?.content == content { return false }
        let old = entries.first(where: { $0.content == content })
        if let old { remove(old.id) }
        entries.insert(Entry(id: old?.id ?? UUID(), content: content), at: 0)
        byteCount += content.byteCount
        while entries.count > maximumCount || byteCount > maximumBytes {
            byteCount -= entries.removeLast().content.byteCount
        }
        return true
    }
    public mutating func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        byteCount -= entries.remove(at: index).content.byteCount
    }
    public mutating func clear() { entries.removeAll(); byteCount = 0 }
}

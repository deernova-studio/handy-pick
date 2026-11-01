/// Latches whether a physical press was passed or consumed until its matching release.
public struct KeyPressGate {
    public enum Result: Equatable { case pass, consume, press }
    private var held: [UInt16: Bool] = [:]
    public init() {}
    public func heldResult(code: UInt16) -> Result? {
        held[code].map { $0 ? .consume : .pass }
    }
    public mutating func down(binding: ShortcutBinding, code: UInt16, flags: UInt64, repeating: Bool,
                              allowShortcut: Bool = true) -> Result {
        if let result = heldResult(code: code) { return result }
        // A repeat with no initial press belongs to an existing OS key sequence.
        guard !repeating, binding.matchesKey(code, flags: flags) else { return .pass }
        held[code] = allowShortcut
        return allowShortcut ? .press : .pass
    }
    public mutating func up(code: UInt16) -> Result { held.removeValue(forKey: code) == true ? .consume : .pass }
    public mutating func reset() { held.removeAll() }
}

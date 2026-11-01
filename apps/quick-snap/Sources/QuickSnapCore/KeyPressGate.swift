/// Separates a fresh physical press from key repeat, and pairs swallowed key-up events.
public struct KeyPressGate {
    public enum Result: Equatable { case pass, consume, press }
    private var held: Set<UInt16> = []
    public init() {}
    public mutating func down(binding: ShortcutBinding, code: UInt16, flags: UInt64, repeating: Bool) -> Result {
        guard binding.matchesKey(code, flags: flags) else { return .pass }
        guard !repeating, held.insert(code).inserted else { return .consume }
        return .press
    }
    public mutating func up(code: UInt16) -> Result { held.remove(code) == nil ? .pass : .consume }
    public mutating func reset() { held.removeAll() }
}

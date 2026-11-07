import Foundation

public enum ShortcutBinding: Codable, Equatable {
    case mouse(Int64)
    case key(UInt16, UInt64)
    case modifier(UInt16)

    public static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    public var isValid: Bool {
        switch self {
        case .mouse(let button): return (2...31).contains(button)
        case .key(let code, let flags):
            return code < 128 && code != 53 && !Self.isModifier(code) && flags & ~Self.modifierMask == 0
        case .modifier(let code): return Self.isModifier(code)
        }
    }

    /// Only unmodified typing keys need focus protection. Every explicitly
    /// configured modifier chord, including Shift-only, remains a shortcut.
    public var needsTypingProtection: Bool {
        guard case .key(let code, let flags) = self else { return false }
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        return flags & Self.modifierMask == 0 && !functionKeys.contains(code)
    }

    public static func isModifier(_ code: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    public func matchesKey(_ code: UInt16, flags: UInt64) -> Bool {
        guard case .key(let expected, let modifiers) = self else { return false }
        return expected == code && flags & Self.modifierMask == modifiers
    }
}

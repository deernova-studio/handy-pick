import Foundation
import CoreGraphics

public enum ShortcutMode: String, Codable, CaseIterable {
    case doublePress
    case chord

    public func accepts(_ binding: ShortcutBinding) -> Bool {
        guard binding.isValid else { return false }
        if self == .doublePress { return true }
        guard case .key(_, let flags) = binding else { return false }
        // Shift-only chords are also explicit shortcuts in chord mode.
        return flags & ShortcutBinding.modifierMask != 0
    }

    public func allowsActivation(for binding: ShortcutBinding,
                                 focusAllowsShortcut: @autoclosure () -> Bool) -> Bool {
        guard accepts(binding) else { return false }
        // Only double-press typing keys need focus protection. Chords must not
        // query focus at all, including in editors or when AX is unavailable.
        return self == .chord || !binding.needsTypingProtection || focusAllowsShortcut()
    }
}

/// KeyPressGate handles physical repeats; this reducer chooses single vs double activation.
public struct ShortcutRecognizer {
    private var clicks: ClickRecognizer
    public init(interval: TimeInterval) { clicks = ClickRecognizer(interval: interval) }
    public mutating func press(mode: ShortcutMode, at time: TimeInterval, point: CGPoint, target: Int32) -> ClickRecognizer.Gesture? {
        if mode == .chord {
            clicks.cancel()
            return ClickRecognizer.Gesture(target: target, point: point)
        }
        return clicks.press(at: time, point: point, target: target)
    }
    public mutating func cancel() { clicks.cancel() }
}

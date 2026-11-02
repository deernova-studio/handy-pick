import Foundation
import CoreGraphics

public enum ShortcutMode: String, Codable, CaseIterable {
    case doublePress
    case chord

    public func accepts(_ binding: ShortcutBinding) -> Bool {
        guard binding.isValid else { return false }
        if self == .doublePress { return true }
        guard case .key(_, let flags) = binding else { return false }
        // Shift alone still types text; require a deliberate shortcut modifier.
        return flags & ((1 << 18) | (1 << 19) | (1 << 20)) != 0
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

import Foundation
import CoreGraphics

/// Input-independent gesture reducer. The event adapter chooses the physical button.
public struct ClickRecognizer {
    public struct Press {
        public let time: TimeInterval
        public let point: CGPoint
        public let target: Int32
    }
    public enum Action: Equatable {
        case scheduleSingle(TimeInterval)
        case cancelSingle
        case capture(Int32)
        case paste(Int32)
    }
    public let interval: TimeInterval
    public let tolerance: CGFloat
    private var pending: Press?

    public init(interval: TimeInterval, tolerance: CGFloat = 6) {
        self.interval = max(0.1, interval)
        self.tolerance = tolerance
    }

    public mutating func press(at time: TimeInterval, point: CGPoint, target: Int32) -> [Action] {
        let new = Press(time: time, point: point, target: target)
        if let old = pending, time >= old.time, time - old.time <= interval,
           old.target == target, hypot(point.x - old.point.x, point.y - old.point.y) <= tolerance {
            pending = nil
            return [.cancelSingle, .paste(target)]
        }
        // A changed target or distant second press must never paste into a different app.
        pending = new
        return [.cancelSingle, .scheduleSingle(time + interval)]
    }

    public mutating func singleDue(at time: TimeInterval) -> Action? {
        guard let press = pending, time >= press.time + interval else { return nil }
        pending = nil
        return .capture(press.target)
    }

    public mutating func cancel() { pending = nil }
}

import Foundation
import CoreGraphics

/// Input-independent gesture reducer. The event adapter chooses the physical button.
public struct ClickRecognizer {
    private struct Press {
        public let time: TimeInterval
        public let point: CGPoint
        public let target: Int32
    }
    public struct Gesture: Equatable {
        public let target: Int32
        public let point: CGPoint
        public init(target: Int32, point: CGPoint) { self.target = target; self.point = point }
    }
    public let interval: TimeInterval
    public let tolerance: CGFloat
    private var pending: Press?

    public init(interval: TimeInterval, tolerance: CGFloat = 6) {
        self.interval = max(0.1, interval)
        self.tolerance = tolerance
    }

    public mutating func press(at time: TimeInterval, point: CGPoint, target: Int32) -> Gesture? {
        let new = Press(time: time, point: point, target: target)
        if let old = pending, time >= old.time, time - old.time <= interval,
           old.target == target, hypot(point.x - old.point.x, point.y - old.point.y) <= tolerance {
            pending = nil
            return Gesture(target: target, point: point)
        }
        // Single clicks never perform work; the next matching press completes the gesture.
        pending = new
        return nil
    }

    public mutating func cancel() { pending = nil }
}

import Foundation

/// Uses one clock for the gesture deadline, and never drops an early timer delivery.
public final class ClickTimer {
    public typealias Enqueue = (TimeInterval, @escaping () -> Void) -> Void
    private let now: () -> TimeInterval
    private let enqueue: Enqueue
    private var generation: UInt64 = 0

    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                enqueue: @escaping Enqueue = { delay, work in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }) {
        self.now = now
        self.enqueue = enqueue
    }

    public func schedule(deadline: TimeInterval, action: @escaping (TimeInterval) -> Void) {
        cancel()
        arm(deadline: deadline, generation: generation, action: action)
    }

    public func cancel() { generation &+= 1 }

    private func arm(deadline: TimeInterval, generation token: UInt64,
                     action: @escaping (TimeInterval) -> Void) {
        // Calculate the remaining duration BEFORE enqueue anchors DispatchTime.now().
        let remaining = max(0.001, deadline - now())
        enqueue(remaining) { [weak self] in
            guard let self, self.generation == token else { return }
            let time = self.now()
            guard time >= deadline else {
                self.arm(deadline: deadline, generation: token, action: action)
                return
            }
            action(time)
        }
    }
}

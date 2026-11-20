import Foundation

/// Pure timing state machine for detecting a double Cmd+C gesture.
public struct DoubleCopyDetector: Sendable {
    public var maxInterval: TimeInterval
    public var cooldown: TimeInterval

    private var lastPressTime: TimeInterval?
    private var lastTriggerTime: TimeInterval?

    public init(maxInterval: TimeInterval = 0.45, cooldown: TimeInterval = 0.55) {
        self.maxInterval = maxInterval
        self.cooldown = cooldown
    }

    /// Registers a Cmd+C press at `timestamp` (in seconds).
    /// Returns `true` when this press completes a valid double Cmd+C.
    public mutating func registerPress(at timestamp: TimeInterval) -> Bool {
        if let lastTrigger = lastTriggerTime, (timestamp - lastTrigger) < cooldown {
            lastPressTime = nil
            return false
        }

        defer {
            // Updated in branches below
        }

        if let previous = lastPressTime {
            let delta = timestamp - previous
            if delta >= 0 && delta <= maxInterval {
                lastPressTime = nil
                lastTriggerTime = timestamp
                return true
            }
        }

        lastPressTime = timestamp
        return false
    }

    public mutating func reset() {
        lastPressTime = nil
        lastTriggerTime = nil
    }
}

import CoreGraphics
import Foundation

/// Tracks continuous screen usage and decides when a look-away break is due.
///
/// Usage time only accumulates while the user is actually at the machine. Any of
/// the following resets the cycle back to a full interval:
///   - the screen locks, the display sleeps, the Mac sleeps, or the screensaver starts
///   - the user is idle (no keyboard / mouse input) for `idleReset` seconds
final class BreakScheduler {
    enum Phase: Equatable {
        case working   // counting down to the next break
        case warning   // last few seconds before a break, reminder pill visible
        case onBreak   // look-away break in progress
    }

    struct Config {
        var workInterval: TimeInterval
        var breakDuration: TimeInterval
        var warningLead: TimeInterval
        var idleReset: TimeInterval

        static let breakDurationKey = "breakDuration"
        static let breakDurationRange: ClosedRange<TimeInterval> = 5...60

        static var standard: Config {
            // LOOKAWAY_DEBUG=1 shortens everything so the flow can be checked quickly.
            var config = ProcessInfo.processInfo.environment["LOOKAWAY_DEBUG"] != nil
                ? Config(workInterval: 30, breakDuration: 10, warningLead: 5, idleReset: 45)
                : Config(workInterval: 20 * 60, breakDuration: 10, warningLead: 5, idleReset: 5 * 60)
            // Break length chosen with the dial on the overlay.
            let saved = UserDefaults.standard.double(forKey: breakDurationKey)
            if breakDurationRange.contains(saved) { config.breakDuration = saved }
            return config
        }
    }

    private(set) var config: Config

    private(set) var phase: Phase = .working {
        didSet { if phase != oldValue { onPhaseChange?(oldValue, phase) } }
    }
    private(set) var worked: TimeInterval = 0
    private(set) var target: TimeInterval
    private(set) var breakRemaining: TimeInterval = 0
    private(set) var pausedUntil: Date?
    /// Break countdown is frozen while the user adjusts the break length on the overlay.
    private(set) var breakHeld = false

    private var suspendReasons = Set<String>()
    private var lastTick = Date()
    private var timer: Timer?

    var onPhaseChange: ((Phase, Phase) -> Void)?
    var onTick: (() -> Void)?

    var remaining: TimeInterval { max(0, target - worked) }
    var isPaused: Bool { pausedUntil != nil }
    var isSuspended: Bool { !suspendReasons.isEmpty }

    init(config: Config = .standard) {
        self.config = config
        self.target = config.workInterval
    }

    func start() {
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Actions

    func startBreak() {
        guard !isPaused else { return }
        breakRemaining = config.breakDuration
        phase = .onBreak
        onTick?()
    }

    func skipBreak() { resetCycle() }

    func holdBreak(_ held: Bool) {
        breakHeld = held
        onTick?()
    }

    /// Saves a new break length. If a break is running it restarts with the new length.
    func setBreakDuration(_ seconds: TimeInterval) {
        let clamped = min(max(seconds, Config.breakDurationRange.lowerBound), Config.breakDurationRange.upperBound)
        config.breakDuration = clamped
        UserDefaults.standard.set(clamped, forKey: Config.breakDurationKey)
        breakHeld = false
        if phase == .onBreak { breakRemaining = clamped }
        onTick?()
    }

    func snooze(_ seconds: TimeInterval) {
        target = worked + seconds
        phase = .working
        onTick?()
    }

    func resetCycle() {
        worked = 0
        target = config.workInterval
        breakRemaining = 0
        breakHeld = false
        phase = .working
        onTick?()
    }

    func pause(until date: Date) {
        pausedUntil = date
        resetCycle()
    }

    func resume() {
        pausedUntil = nil
        lastTick = Date()
        resetCycle()
    }

    /// Stop counting (lock, sleep, ...) and start over from a full interval.
    func suspend(_ reason: String) {
        suspendReasons.insert(reason)
        resetCycle()
    }

    func unsuspend(_ reason: String) {
        guard suspendReasons.remove(reason) != nil else { return }
        if !isSuspended {
            lastTick = Date()
            resetCycle()
        }
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        // Cap the delta so a missed wake/unlock notification can't count a long gap as usage.
        let dt = min(max(now.timeIntervalSince(lastTick), 0), 2)
        lastTick = now
        defer { onTick?() }

        if let until = pausedUntil {
            if now >= until { resume() }
            return
        }

        if isSuspended {
            // Safety net in case an "unlocked"/"woke" notification was missed:
            // the user is clearly back if there is fresh input on an unlocked screen.
            if Self.idleSeconds() < 2, !Self.isScreenLocked() {
                suspendReasons.removeAll()
                resetCycle()
            }
            return
        }

        switch phase {
        case .onBreak:
            guard !breakHeld else { return }
            breakRemaining -= dt
            if breakRemaining <= 0 { resetCycle() }
        case .working, .warning:
            if Self.idleSeconds() >= config.idleReset {
                // User walked away long enough – that counts as a rest.
                if worked > 0 || phase != .working { resetCycle() }
                return
            }
            worked += dt
            if remaining <= 0 {
                startBreak()
            } else if remaining <= config.warningLead {
                phase = .warning
            }
        }
    }

    // MARK: - System state helpers

    static func idleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

import CoreGraphics
import Foundation

/// Tracks continuous screen usage and decides when a look-away break is due.
///
/// Usage time only accumulates while the user is actually at the machine. Any of
/// the following resets the cycle back to a full interval:
///   - the screen locks, the display sleeps, the Mac sleeps, or the screensaver starts
///   - the user is idle (no keyboard / mouse input) for `idleReset` seconds
///
/// It also runs a slower water timer on the same active-use clock. When water is due,
/// the next eye break doubles as a water break. Locking only pauses the water timer;
/// being away for `waterAwayReset` resets it (the user probably had a drink).
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
        var waterInterval: TimeInterval
        var waterAwayReset: TimeInterval

        static let breakDurationKey = "breakDuration"
        static let workIntervalKey = "workInterval"
        static let waterIntervalKey = "waterInterval"
        static let breakDurationRange: ClosedRange<TimeInterval> = 5...60
        static let workIntervalRange: ClosedRange<TimeInterval> = 5 * 60...90 * 60
        static let waterIntervalRange: ClosedRange<TimeInterval> = 15 * 60...180 * 60

        static var standard: Config {
            let defaults = UserDefaults.standard
            // LOOKAWAY_DEBUG=1 shortens everything so the flow can be checked quickly.
            let debug = ProcessInfo.processInfo.environment["LOOKAWAY_DEBUG"] != nil
            var config = debug
                ? Config(workInterval: 30, breakDuration: 10, warningLead: 5, idleReset: 45,
                         waterInterval: 50, waterAwayReset: 90)
                : Config(workInterval: 20 * 60, breakDuration: 10, warningLead: 5, idleReset: 5 * 60,
                         waterInterval: 60 * 60, waterAwayReset: 30 * 60)
            // Values chosen in the menu / overlay dial. Debug mode keeps its short intervals.
            let breakDuration = defaults.double(forKey: breakDurationKey)
            if breakDurationRange.contains(breakDuration) { config.breakDuration = breakDuration }
            if !debug {
                let work = defaults.double(forKey: workIntervalKey)
                if workIntervalRange.contains(work) { config.workInterval = work }
                let water = defaults.double(forKey: waterIntervalKey)
                if waterIntervalRange.contains(water) { config.waterInterval = water }
            }
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

    private(set) var waterWorked: TimeInterval = 0
    /// Water timer has elapsed; the next eye break will mention water.
    var waterDue: Bool { waterWorked >= config.waterInterval }
    /// A water break has been shown but no glass was logged yet (menu bar shows a drop).
    private(set) var waterPending = false
    /// The running (or about to start) break is also a water break.
    private(set) var isWaterBreak = false
    private var suspendedAt: Date?

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
        isWaterBreak = waterDue
        if isWaterBreak { waterPending = true }
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

    /// Saves a new screen-time interval and applies it to the running cycle.
    func setWorkInterval(_ seconds: TimeInterval) {
        let value = Self.clamp(seconds, Config.workIntervalRange)
        config.workInterval = value
        UserDefaults.standard.set(value, forKey: Config.workIntervalKey)
        // Never drop straight into a break because the interval shrank below time already worked.
        if phase == .working { target = max(value, worked + 60) }
        onTick?()
    }

    func setWaterInterval(_ seconds: TimeInterval) {
        let value = Self.clamp(seconds, Config.waterIntervalRange)
        config.waterInterval = value
        UserDefaults.standard.set(value, forKey: Config.waterIntervalKey)
        onTick?()
    }

    private static func clamp(_ v: TimeInterval, _ range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(v, range.lowerBound), range.upperBound)
    }

    /// User logged a glass: start the water timer over.
    func drankWater() {
        resetWater()
        onTick?()
    }

    private func resetWater() {
        waterWorked = 0
        waterPending = false
        isWaterBreak = false
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
        isWaterBreak = false
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
        if suspendReasons.isEmpty { suspendedAt = Date() }
        suspendReasons.insert(reason)
        resetCycle()
    }

    func unsuspend(_ reason: String) {
        guard suspendReasons.remove(reason) != nil else { return }
        if !isSuspended { returnFromAway() }
    }

    private func returnFromAway() {
        if let since = suspendedAt, Date().timeIntervalSince(since) >= config.waterAwayReset {
            resetWater()
        }
        suspendedAt = nil
        lastTick = Date()
        resetCycle()
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
                returnFromAway()
            }
            return
        }

        switch phase {
        case .onBreak:
            waterWorked += dt
            guard !breakHeld else { return }
            breakRemaining -= dt
            if breakRemaining <= 0 { resetCycle() }
        case .working, .warning:
            let idle = Self.idleSeconds()
            if idle >= config.idleReset {
                // User walked away long enough – that counts as a rest.
                if worked > 0 || phase != .working { resetCycle() }
                if idle >= config.waterAwayReset, waterWorked > 0 || waterPending { resetWater() }
                return
            }
            worked += dt
            waterWorked += dt
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

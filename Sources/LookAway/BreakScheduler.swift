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
///
/// A posture timer runs on the same clock and fires a short nudge (`onPostureDue`).
/// Any time away (lock, sleep, idle reset) restarts it, since the user got up.
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
        var postureInterval: TimeInterval
        var waterEnabled = true
        var postureEnabled = true
        var holdDuringCalls = true

        static let breakDurationKey = "breakDuration"
        static let workIntervalKey = "workInterval"
        static let waterIntervalKey = "waterInterval"
        static let postureIntervalKey = "postureInterval"
        static let waterEnabledKey = "waterEnabled"
        static let postureEnabledKey = "postureEnabled"
        static let holdDuringCallsKey = "holdDuringCalls"
        static let breakDurationRange: ClosedRange<TimeInterval> = 5...60
        static let workIntervalRange: ClosedRange<TimeInterval> = 5 * 60...90 * 60
        static let waterIntervalRange: ClosedRange<TimeInterval> = 15 * 60...180 * 60
        static let postureIntervalRange: ClosedRange<TimeInterval> = 10 * 60...120 * 60

        static var standard: Config {
            let defaults = UserDefaults.standard
            // LOOKAWAY_DEBUG=1 shortens everything so the flow can be checked quickly.
            let debug = ProcessInfo.processInfo.environment["LOOKAWAY_DEBUG"] != nil
            var config = debug
                ? Config(workInterval: 30, breakDuration: 20, warningLead: 5, idleReset: 45,
                         waterInterval: 50, waterAwayReset: 90, postureInterval: 15)
                : Config(workInterval: 20 * 60, breakDuration: 20, warningLead: 5, idleReset: 5 * 60,
                         waterInterval: 60 * 60, waterAwayReset: 30 * 60, postureInterval: 30 * 60)
            // Values chosen in the menu / overlay dial. Debug mode keeps its short intervals.
            let breakDuration = defaults.double(forKey: breakDurationKey)
            if breakDurationRange.contains(breakDuration) { config.breakDuration = breakDuration }
            if !debug {
                let work = defaults.double(forKey: workIntervalKey)
                if workIntervalRange.contains(work) { config.workInterval = work }
                let water = defaults.double(forKey: waterIntervalKey)
                if waterIntervalRange.contains(water) { config.waterInterval = water }
                let posture = defaults.double(forKey: postureIntervalKey)
                if postureIntervalRange.contains(posture) { config.postureInterval = posture }
            }
            // Both reminders default to on when never toggled.
            config.waterEnabled = defaults.object(forKey: waterEnabledKey) as? Bool ?? true
            config.postureEnabled = defaults.object(forKey: postureEnabledKey) as? Bool ?? true
            config.holdDuringCalls = defaults.object(forKey: holdDuringCallsKey) as? Bool ?? true
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
    var waterDue: Bool { config.waterEnabled && waterWorked >= config.waterInterval }
    /// A water break has been shown but no glass was logged yet (menu bar shows a drop).
    private(set) var waterPending = false
    /// The running (or about to start) break is also a water break.
    private(set) var isWaterBreak = false
    private var suspendedAt: Date?

    private(set) var postureWorked: TimeInterval = 0
    /// Called when it's time for a posture nudge; only fires while no break UI is up.
    var onPostureDue: (() -> Void)?

    /// Returns true while the user is in a call / presenting (mic, camera or screen share).
    var callCheck: (() -> Bool)?
    /// Breaks and nudges are being held because of a call.
    private(set) var inCall = false
    /// Started from the menu: the user asked for it, so a call doesn't cancel it.
    private var manualBreak = false
    /// Quiet time after a call ends before an overdue break is offered.
    private let afterCallGrace: TimeInterval = 15

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

    func startBreak(manual: Bool = false) {
        guard !isPaused else { return }
        manualBreak = manual
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

    func setPostureInterval(_ seconds: TimeInterval) {
        let value = Self.clamp(seconds, Config.postureIntervalRange)
        config.postureInterval = value
        UserDefaults.standard.set(value, forKey: Config.postureIntervalKey)
        onTick?()
    }

    func setWaterEnabled(_ enabled: Bool) {
        config.waterEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Config.waterEnabledKey)
        resetWater()
        onTick?()
    }

    func setPostureEnabled(_ enabled: Bool) {
        config.postureEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Config.postureEnabledKey)
        postureWorked = 0
        onTick?()
    }

    func setHoldDuringCalls(_ enabled: Bool) {
        config.holdDuringCalls = enabled
        UserDefaults.standard.set(enabled, forKey: Config.holdDuringCallsKey)
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
        postureWorked = 0
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

        let held = config.holdDuringCalls && (callCheck?() ?? false)
        if held != inCall {
            inCall = held
            // Call ended: give a moment to hang up before an overdue break shows.
            if !held, phase == .working, remaining < afterCallGrace {
                target = worked + afterCallGrace
            }
        }

        switch phase {
        case .onBreak:
            if config.waterEnabled { waterWorked += dt }
            if held, !manualBreak {
                // A call started (e.g. joining a meeting): get out of the way, offer the break later.
                waterPending = false
                isWaterBreak = false
                breakRemaining = 0
                breakHeld = false
                phase = .working
                return
            }
            guard !breakHeld else { return }
            breakRemaining -= dt
            if breakRemaining <= 0 { resetCycle() }
        case .working, .warning:
            let idle = Self.idleSeconds()
            // In a call the user is watching the screen even without typing, so no idle reset.
            if idle >= config.idleReset, !held {
                // User walked away long enough – that counts as a rest.
                if worked > 0 || phase != .working { resetCycle() }
                if idle >= config.waterAwayReset, waterWorked > 0 || waterPending { resetWater() }
                postureWorked = 0
                return
            }
            worked += dt
            if config.waterEnabled { waterWorked += dt }
            if config.postureEnabled { postureWorked += dt }
            if held {
                // Keep counting, but show nothing until the call is over.
                if phase == .warning { phase = .working }
                return
            }
            if remaining <= 0 {
                startBreak()
            } else if remaining <= config.warningLead {
                phase = .warning
            } else if config.postureEnabled, postureWorked >= config.postureInterval,
                      remaining > config.warningLead + 10 {
                // Hold the nudge while a break is about to start; it shows after the break instead.
                postureWorked = 0
                onPostureDue?()
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

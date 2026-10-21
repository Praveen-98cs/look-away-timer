import CoreGraphics
import Foundation

/// Tracks continuous screen usage and decides when a look-away break is due.
///
/// Usage time only accumulates while the user is actually at the machine. Any of
/// the following resets the cycle back to a full interval:
///   - the screen locks, the display sleeps, the Mac sleeps, or the screensaver starts
///   - the user is idle (no keyboard / mouse input) for `idleReset` seconds
///
/// Water and posture timers run on the same active-use clock and fire short nudges
/// (`onNudgeDue`). Locking only pauses the water timer; being away for `waterAwayReset`
/// resets it (the user probably had a drink). Any time away restarts the posture timer.
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
        /// Length of a "minute" for custom popup intervals (shortened in debug runs).
        var customMinute: TimeInterval = 60

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
            // HEALTHYPOPS_DEBUG=1 shortens everything so the flow can be checked quickly.
            let debug = ProcessInfo.processInfo.environment["HEALTHYPOPS_DEBUG"] != nil
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
            if debug { config.customMinute = 3 }
            return config
        }
    }

    private(set) var config: Config

    private(set) var phase: Phase = .working {
        didSet {
            guard phase != oldValue else { return }
            Self.debugLog("phase \(oldValue) -> \(phase)")
            onPhaseChange?(oldValue, phase)
        }
    }
    private(set) var worked: TimeInterval = 0
    private(set) var target: TimeInterval
    private(set) var breakRemaining: TimeInterval = 0
    private(set) var pausedUntil: Date?
    /// Break countdown is frozen while the user adjusts the break length on the overlay.
    private(set) var breakHeld = false

    private(set) var waterWorked: TimeInterval = 0
    private(set) var postureWorked: TimeInterval = 0
    private var customWorked: [UUID: TimeInterval] = [:]
    /// Source of custom popups to schedule.
    var customPopups: () -> [CustomPopup] = { [] }
    /// Set while the app's own full-screen UI (e.g. the popup editor) is open: keep counting, show nothing.
    var uiHold = false
    private var suspendedAt: Date?

    /// Called when a water or posture nudge is due; only fires while no break UI is up.
    var onNudgeDue: ((NudgeKind) -> Void)?

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
        Self.debugLog("started")
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

    /// Start a custom popup's timer over (after it was created or edited).
    func resetCustom(id: UUID) {
        customWorked[id] = 0
    }

    private func resetWater() {
        waterWorked = 0
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
        customWorked.removeAll()
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

        let callHeld = config.holdDuringCalls && (callCheck?() ?? false)
        if callHeld != inCall {
            inCall = callHeld
            // Call ended: give a moment to hang up before an overdue break shows.
            if !callHeld, phase == .working, remaining < afterCallGrace {
                target = worked + afterCallGrace
            }
        }
        let held = callHeld || uiHold

        switch phase {
        case .onBreak:
            if config.waterEnabled { waterWorked += dt }
            if held, !manualBreak {
                // A call started (e.g. joining a meeting): get out of the way, offer the break later.
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
                if worked > 0 || phase != .working {
                    Self.debugLog("idle \(Int(idle))s: cycle reset")
                    resetCycle()
                }
                if idle >= config.waterAwayReset { resetWater() }
                postureWorked = 0
                customWorked.removeAll()
                return
            }
            worked += dt
            if config.waterEnabled { waterWorked += dt }
            if config.postureEnabled { postureWorked += dt }
            let custom = customPopups().filter(\.enabled)
            for popup in custom { customWorked[popup.id, default: 0] += dt }
            if held {
                // Keep counting, but show nothing until the call is over.
                if phase == .warning { phase = .working }
                return
            }
            if remaining <= 0 {
                startBreak()
            } else if remaining <= config.warningLead {
                phase = .warning
            } else if remaining > config.warningLead + 10 {
                // Nudges wait while a break is about to start; they show after it instead.
                if config.waterEnabled, waterWorked >= config.waterInterval {
                    waterWorked = 0
                    Self.debugLog("nudge water")
                    onNudgeDue?(.water)
                }
                if config.postureEnabled, postureWorked >= config.postureInterval {
                    postureWorked = 0
                    Self.debugLog("nudge posture")
                    onNudgeDue?(.posture)
                }
                for popup in custom where customWorked[popup.id, default: 0]
                    >= TimeInterval(popup.intervalMinutes) * config.customMinute {
                    customWorked[popup.id] = 0
                    Self.debugLog("nudge custom \(popup.title)")
                    onNudgeDue?(.custom(popup))
                }
            }
        }
    }

    // MARK: - System state helpers

    private static let debugStart = Date()
    private static let debugEnabled = ProcessInfo.processInfo.environment["HEALTHYPOPS_DEBUG"] != nil

    /// Timeline log for HEALTHYPOPS_DEBUG runs; silent otherwise.
    static func debugLog(_ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        print(String(format: "[%5.1fs] ", Date().timeIntervalSince(debugStart)) + message())
        fflush(stdout)
    }

    static func idleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

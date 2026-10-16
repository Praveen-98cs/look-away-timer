import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let scheduler = BreakScheduler()
    private let reminder = ReminderPanelController()
    private let overlay = BreakOverlayController()
    private let posture = PostureToastController()

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the 1s timer accurate; App Nap would otherwise throttle a background accessory app.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Tracking screen time for eye breaks"
        )

        setUpStatusItem()
        wireScheduler()
        observeSystemEvents()
        scheduler.start()
        refreshStatusItem()
    }

    // MARK: - Wiring

    private func wireScheduler() {
        reminder.onStartBreak = { [weak self] in self?.scheduler.startBreak() }
        reminder.onSnooze = { [weak self] s in self?.scheduler.snooze(s) }
        overlay.onSkip = { [weak self] in self?.scheduler.skipBreak() }
        overlay.onAdjustingChange = { [weak self] held in self?.scheduler.holdBreak(held) }
        overlay.onDurationApply = { [weak self] s in self?.scheduler.setBreakDuration(TimeInterval(s)) }
        overlay.onDrankWater = { [weak self] in self?.logWater() ?? WaterLog.today }

        scheduler.onPostureDue = { [weak self] in self?.posture.show() }
        scheduler.callCheck = { CallDetector.isInCall() }

        scheduler.onPhaseChange = { [weak self] old, new in
            guard let self else { return }
            if new != .warning { reminder.hide() }
            if new != .working { posture.hide() }   // the eye reminder takes the same spot
            if old == .onBreak {
                overlay.hide()
                NSSound(named: "Glass")?.play()
            }
        }

        scheduler.onTick = { [weak self] in
            guard let self else { return }
            switch scheduler.phase {
            case .warning:
                reminder.show(
                    remaining: scheduler.remaining,
                    total: scheduler.config.warningLead,
                    breakDuration: scheduler.config.breakDuration,
                    water: scheduler.waterDue
                )
            case .onBreak:
                overlay.show(breakDuration: Int(scheduler.config.breakDuration), water: scheduler.isWaterBreak)
                overlay.update(remaining: scheduler.breakRemaining, total: scheduler.config.breakDuration)
            case .working:
                if scheduler.inCall { posture.hide() }
            }
            refreshStatusItem()
        }
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let pairs: [(NSNotification.Name, NSNotification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for (down, up, reason) in pairs {
            ws.addObserver(forName: down, object: nil, queue: .main) { [weak self] _ in self?.scheduler.suspend(reason) }
            ws.addObserver(forName: up, object: nil, queue: .main) { [weak self] _ in self?.scheduler.unsuspend(reason) }
        }

        let dnc = DistributedNotificationCenter.default()
        let distributed: [(String, String, String)] = [
            ("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "lock"),
            ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "screensaver"),
        ]
        for (down, up, reason) in distributed {
            dnc.addObserver(forName: .init(down), object: nil, queue: .main) { [weak self] _ in self?.scheduler.suspend(reason) }
            dnc.addObserver(forName: .init(up), object: nil, queue: .main) { [weak self] _ in self?.scheduler.unsuspend(reason) }
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let title: String

        if scheduler.isPaused {
            symbol = "eye.slash"
            title = ""
        } else {
            switch scheduler.phase {
            case .onBreak:
                symbol = "eyes"
                title = " \(Int(scheduler.breakRemaining.rounded(.up)))s"
            case .warning:
                symbol = "eyes"
                title = " " + formatClock(scheduler.remaining)
            case .working where scheduler.inCall:
                symbol = "phone.fill"
                let r = scheduler.remaining
                title = r <= 0 ? " later" : r >= 60 ? " \(Int((r / 60).rounded(.up)))m" : " \(Int(r.rounded(.up)))s"
            case .working:
                // A water break went by without a logged glass: the eyes become a drop until logged.
                symbol = scheduler.waterPending ? "drop.fill" : "eyes"
                let r = scheduler.remaining
                title = r >= 60 ? " \(Int((r / 60).rounded(.up)))m" : " \(Int(r.rounded(.up)))s"
            }
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Look Away")
        image?.isTemplate = true
        button.image = image
        button.title = title
        statusLine.title = statusDescription()
    }

    private func statusDescription() -> String {
        if let until = scheduler.pausedUntil {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if scheduler.isSuspended { return "Away – timer reset" }
        switch scheduler.phase {
        case .onBreak: return "Break in progress"
        case .warning: return "Break starting…"
        case .working:
            if scheduler.inCall { return "In a call. Breaks will wait." }
            if scheduler.waterPending { return "Time for some water" }
            let r = scheduler.remaining
            return r >= 60
                ? "Next break in \(Int((r / 60).rounded(.up))) min"
                : "Next break in \(Int(r.rounded(.up))) sec"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        statusLine.isEnabled = false
        statusLine.title = statusDescription()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        if scheduler.config.waterEnabled {
            let waterCount = NSMenuItem(title: "Water today: \(WaterLog.today) / \(WaterLog.dailyGoal) glasses",
                                        action: nil, keyEquivalent: "")
            waterCount.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil)
            waterCount.isEnabled = false
            menu.addItem(waterCount)
            menu.addItem(item("I Drank Water", #selector(drankWaterFromMenu), key: "w"))
            menu.addItem(.separator())
        }

        let breakNow = item("Take a Break Now", #selector(takeBreakNow), key: "b")
        breakNow.isEnabled = !scheduler.isPaused && scheduler.phase != .onBreak
        menu.addItem(breakNow)
        menu.addItem(item("Reset Timer", #selector(resetTimer), key: "r"))
        menu.addItem(.separator())

        let remindersHeader = NSMenuItem(title: "Reminders", action: nil, keyEquivalent: "")
        remindersHeader.isEnabled = false
        menu.addItem(remindersHeader)
        let waterToggle = item("Water Reminders", #selector(toggleWater), key: "")
        waterToggle.state = scheduler.config.waterEnabled ? .on : .off
        menu.addItem(waterToggle)
        let postureToggle = item("Posture Reminders", #selector(togglePosture), key: "")
        postureToggle.state = scheduler.config.postureEnabled ? .on : .off
        menu.addItem(postureToggle)
        let callToggle = item("Hold Breaks During Calls", #selector(toggleHoldDuringCalls), key: "")
        callToggle.state = scheduler.config.holdDuringCalls ? .on : .off
        menu.addItem(callToggle)
        menu.addItem(.separator())

        let timersHeader = NSMenuItem(title: "Timers", action: nil, keyEquivalent: "")
        timersHeader.isEnabled = false
        menu.addItem(timersHeader)
        menu.addItem(.stepper(title: "Screen time", value: minutes(scheduler.config.workInterval)) { [weak self] dir in
            guard let self else { return "" }
            scheduler.setWorkInterval(Self.snap(scheduler.config.workInterval, step: 5 * 60, dir: dir))
            return minutes(scheduler.config.workInterval)
        })
        menu.addItem(.stepper(title: "Look away", value: seconds(scheduler.config.breakDuration)) { [weak self] dir in
            guard let self else { return "" }
            scheduler.setBreakDuration(Self.snap(scheduler.config.breakDuration, step: 5, dir: dir))
            return seconds(scheduler.config.breakDuration)
        })
        if scheduler.config.waterEnabled {
            menu.addItem(.stepper(title: "Water break", value: minutes(scheduler.config.waterInterval)) { [weak self] dir in
                guard let self else { return "" }
                scheduler.setWaterInterval(Self.snap(scheduler.config.waterInterval, step: 15 * 60, dir: dir))
                return minutes(scheduler.config.waterInterval)
            })
        }
        if scheduler.config.postureEnabled {
            menu.addItem(.stepper(title: "Posture", value: minutes(scheduler.config.postureInterval)) { [weak self] dir in
                guard let self else { return "" }
                scheduler.setPostureInterval(Self.snap(scheduler.config.postureInterval, step: 5 * 60, dir: dir))
                return minutes(scheduler.config.postureInterval)
            })
        }
        menu.addItem(.separator())

        if scheduler.isPaused {
            menu.addItem(item("Resume", #selector(resume), key: ""))
        } else {
            let pauseMenu = NSMenu()
            for (title, minutes) in [("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120)] {
                let i = item(title, #selector(pauseFor(_:)), key: "")
                i.tag = minutes
                pauseMenu.addItem(i)
            }
            pauseMenu.addItem(item("Until Tomorrow", #selector(pauseUntilTomorrow), key: ""))
            let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            pause.submenu = pauseMenu
            menu.addItem(pause)
        }
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin), key: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Look Away", #selector(quit), key: "q"))
    }

    /// Next multiple of `step` in direction `dir`, so odd values (e.g. 9 s from the dial) land on the grid.
    private static func snap(_ value: TimeInterval, step: TimeInterval, dir: Int) -> TimeInterval {
        dir > 0
            ? (value / step).rounded(.down) * step + step
            : (value / step).rounded(.up) * step - step
    }

    private func minutes(_ s: TimeInterval) -> String { "\(Int(s / 60)) min" }
    private func seconds(_ s: TimeInterval) -> String { "\(Int(s)) s" }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @discardableResult
    private func logWater() -> Int {
        let count = WaterLog.addGlass()
        scheduler.drankWater()
        return count
    }

    @objc private func drankWaterFromMenu() { logWater() }
    @objc private func toggleHoldDuringCalls() {
        scheduler.setHoldDuringCalls(!scheduler.config.holdDuringCalls)
    }

    @objc private func toggleWater() { scheduler.setWaterEnabled(!scheduler.config.waterEnabled) }

    @objc private func togglePosture() {
        scheduler.setPostureEnabled(!scheduler.config.postureEnabled)
        if !scheduler.config.postureEnabled { posture.hide() }
    }

    @objc private func takeBreakNow() { scheduler.startBreak(manual: true) }
    @objc private func resetTimer() { scheduler.resetCycle() }
    @objc private func resume() { scheduler.resume() }

    @objc private func pauseFor(_ sender: NSMenuItem) {
        scheduler.pause(until: Date().addingTimeInterval(TimeInterval(sender.tag * 60)))
    }

    @objc private func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
        scheduler.pause(until: tomorrow)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Look Away.app to /Applications and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

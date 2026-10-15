import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let scheduler = BreakScheduler()
    private let reminder = ReminderPanelController()
    private let overlay = BreakOverlayController()

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

        scheduler.onPhaseChange = { [weak self] old, new in
            guard let self else { return }
            if new != .warning { reminder.hide() }
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
                    breakDuration: scheduler.config.breakDuration
                )
            case .onBreak:
                overlay.show(breakDuration: Int(scheduler.config.breakDuration))
            case .working:
                break
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
            case .working:
                symbol = "eyes"
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

        let breakNow = item("Take a Break Now", #selector(takeBreakNow), key: "b")
        breakNow.isEnabled = !scheduler.isPaused && scheduler.phase != .onBreak
        menu.addItem(breakNow)
        menu.addItem(item("Reset Timer", #selector(resetTimer), key: "r"))
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

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func takeBreakNow() { scheduler.startBreak() }
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

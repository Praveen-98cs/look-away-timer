import AppKit
import Carbon.HIToolbox
import SwiftUI

final class ReminderModel: ObservableObject {
    @Published var remaining: TimeInterval = 10
    @Published var total: TimeInterval = 10
    @Published var message = ""

    // The instruction lives here, not in the overlay, so nobody reads the overlay during the break.
    static func message(breakDuration: TimeInterval) -> String {
        "Get ready to look away for \(Int(breakDuration)) seconds."
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - remaining / total
    }
}

struct ReminderView: View {
    @ObservedObject var model: ReminderModel
    let onStart: () -> Void
    let onSnooze: (TimeInterval) -> Void

    private static let radius: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ClockBadge(progress: model.progress)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatClock(model.remaining))
                        .font(.system(size: 25, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(model.message)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize()
                }
                Spacer(minLength: 12)
                HStack(spacing: 3) {
                    KeyCap("⌃")
                    KeyCap("⌥")
                    Text("+ key")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            }
            HStack(spacing: 10) {
                Button(action: onStart) { label("Start this break now", key: "B") }
                    .buttonStyle(PillButtonStyle(filled: true))
                Button { onSnooze(60) } label: { label("+1m", key: "1") }
                    .buttonStyle(PillButtonStyle())
                Button { onSnooze(5 * 60) } label: { label("+5m", key: "2") }
                    .buttonStyle(PillButtonStyle())
                Button { onSnooze(15 * 60) } label: { label("+15m", key: "3") }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Palette.navyTop.opacity(0.2), Palette.navyBottom.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private func label(_ title: String, key: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            KeyCap(key)
        }
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The small pill that drops in below the menu bar a few seconds before a break.
final class ReminderPanelController {
    var onStartBreak: (() -> Void)?
    var onSnooze: ((TimeInterval) -> Void)?

    private let model = ReminderModel()
    private var panel: NSPanel?
    private let hotKeys = HotKeys()

    var isVisible: Bool { panel != nil }

    func show(remaining: TimeInterval, total: TimeInterval, breakDuration: TimeInterval) {
        if panel == nil {
            model.message = ReminderModel.message(breakDuration: breakDuration)
            model.total = total
            model.remaining = remaining
            present()
        } else {
            model.remaining = remaining
        }
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        hotKeys.unregisterAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func present() {
        let view = ReminderView(
            model: model,
            onStart: { [weak self] in self?.onStartBreak?() },
            onSnooze: { [weak self] s in self?.onSnooze?(s) }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.maskImage = .roundedMask(radius: 26)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let screen = Self.activeScreen()
        let visible = screen.visibleFrame
        let finalFrame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 44,
            width: size.width,
            height: size.height
        )

        let panel = ReminderPanel(
            contentRect: finalFrame.offsetBy(dx: 0, dy: 12),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = effect
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        // ⌃⌥ + B / 1 / 2 / 3, live only while the pill is visible.
        hotKeys.register(keyCode: kVK_ANSI_B) { [weak self] in self?.onStartBreak?() }
        hotKeys.register(keyCode: kVK_ANSI_1) { [weak self] in self?.onSnooze?(60) }
        hotKeys.register(keyCode: kVK_ANSI_2) { [weak self] in self?.onSnooze?(5 * 60) }
        hotKeys.register(keyCode: kVK_ANSI_3) { [weak self] in self?.onSnooze?(15 * 60) }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    /// Screen under the mouse pointer, falling back to the main screen.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

import AppKit
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
            HStack(spacing: 16) {
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
            }
            HStack(spacing: 10) {
                Button("Start this break now", action: onStart)
                    .buttonStyle(PillButtonStyle(filled: true))
                Button("+1m") { onSnooze(60) }
                    .buttonStyle(PillButtonStyle())
                Button("+5m") { onSnooze(5 * 60) }
                    .buttonStyle(PillButtonStyle())
                Button("+15m") { onSnooze(15 * 60) }
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

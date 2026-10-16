import AppKit
import SwiftUI

final class PostureModel: ObservableObject {
    @Published var message = ""
    @Published var progress: Double = 1   // 1 → 0 over the visible duration

    static let messages = [
        "Shrimp mode detected. Unfold yourself. 🦐",
        "Your spine called. It misses being straight.",
        "You're slowly turning into a question mark. ❓",
        "Uncurl. You're a human, not a croissant. 🥐",
        "Shoulders back, chin up, you magnificent coder.",
        "Sit like you're about to get your photo taken. 📸",
        "Gravity is winning. Fight back.",
        "Imagine a string pulling your head to the ceiling.",
        "Posture check! Your future self says thanks.",
        "Less goblin, more giraffe. 🦒",
    ]
}

struct PostureView: View {
    @ObservedObject var model: PostureModel
    private static let radius: CGFloat = 22

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.mint, Palette.teal],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading,
                                         startRadius: 0, endRadius: 36))
                Image(systemName: "figure.stand")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Palette.teal.opacity(0.45), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Straighten your back")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(model.message)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 22)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [Palette.navyTop.opacity(0.2), Palette.navyBottom.opacity(0.3)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            // Thin bar showing how long the nudge stays.
            GeometryReader { geo in
                Capsule()
                    .fill(Palette.mint.opacity(0.7))
                    .frame(width: geo.size.width * model.progress, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .padding(.horizontal, Self.radius)
            .padding(.bottom, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

/// A short posture nudge below the menu bar. No buttons: it fades out on its own
/// after `duration` seconds, or immediately when clicked.
final class PostureToastController {
    var duration: TimeInterval = 5

    private let model = PostureModel()
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show() {
        hide(animated: false)
        // Avoid repeating the previous message back to back.
        model.message = PostureModel.messages.filter { $0 != model.message }.randomElement() ?? ""
        model.progress = 1

        let hosting = NSHostingView(rootView: PostureView(model: model))
        let size = hosting.fittingSize

        let effect = ClickThroughEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.maskImage = .roundedMask(radius: 22)
        effect.onClick = { [weak self] in self?.hide() }
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let visible = ReminderPanelController.activeScreen().visibleFrame
        let finalFrame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 44,
                                width: size.width, height: size.height)

        let panel = NSPanel(contentRect: finalFrame.offsetBy(dx: 0, dy: 12),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        withAnimation(.linear(duration: duration)) { model.progress = 0 }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide(animated: Bool = true) {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

/// Visual-effect container that reports clicks anywhere on it.
private final class ClickThroughEffectView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }
    override func mouseUp(with event: NSEvent) { onClick?() }
}

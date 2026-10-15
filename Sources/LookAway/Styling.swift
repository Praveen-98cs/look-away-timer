import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let pink = Color(hex: 0xFF4FA3)
    static let coral = Color(hex: 0xF5677E)
    static let peach = Color(hex: 0xEE8B5F)
    static let navyTop = Color(hex: 0x1C1B4D)
    static let navyBottom = Color(hex: 0x121035)
}

extension NSImage {
    /// Stretchable rounded-rect mask, used to give NSVisualEffectView rounded corners.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Capsule button matching the reminder pill: filled for the primary action, outlined otherwise.
struct PillButtonStyle: ButtonStyle {
    var filled = false
    var fontSize: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, filled: filled, fontSize: fontSize)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let filled: Bool
        let fontSize: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.white.opacity(fillOpacity))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.2), lineWidth: 1)
                )
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }

        private var fillOpacity: Double {
            let base = filled ? 0.13 : 0.0
            let hover = hovering ? 0.08 : 0
            let press = configuration.isPressed ? 0.06 : 0
            return base + hover + press
        }
    }
}

/// The pink clock badge from the reminder pill. `progress` (0...1) drives the hand.
struct ClockBadge: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.pink, Palette.coral, Palette.peach],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.28), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: size * 0.8
                        )
                    )
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i % 3 == 0 ? 0.75 : 0.45))
                        .frame(width: size * 0.045, height: size * 0.045)
                        .offset(y: -size * 0.36)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                Capsule()
                    .fill(.white)
                    .frame(width: size * 0.06, height: size * 0.32)
                    .offset(y: -size * 0.13)
                    .rotationEffect(.degrees(progress * 360))
                    .animation(.linear(duration: 1), value: progress)
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.09, height: size * 0.09)
            }
            .frame(width: size, height: size)
            .shadow(color: Palette.pink.opacity(0.45), radius: 8, y: 2)
        }
    }
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

import AppKit

/// Menu row with a title and − / + buttons. Clicking the buttons adjusts the value in
/// place without closing the menu.
final class StepperMenuItemView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let onStep: (Int) -> String

    /// `onStep(+1 / -1)` applies the change and returns the new display string.
    init(title: String, value: String, onStep: @escaping (Int) -> String) {
        self.onStep = onStep
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 28))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)

        valueLabel.stringValue = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        valueLabel.alignment = .center
        valueLabel.textColor = .secondaryLabelColor

        let minus = StepButton(glyph: "−", label: "Decrease \(title)") { [weak self] in self?.step(-1) }
        let plus = StepButton(glyph: "+", label: "Increase \(title)") { [weak self] in self?.step(1) }

        let stack = NSStackView(views: [titleLabel, NSView(), minus, valueLabel, plus])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 64),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func step(_ dir: Int) { valueLabel.stringValue = onStep(dir) }
}

/// Small round − / + button that draws itself. Standard NSButtons inside a menu-item
/// view don't render reliably, so this handles its own drawing, hover and clicks.
private final class StepButton: NSView {
    private let glyph: String
    private let action: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(glyph: String, label: String, action: @escaping () -> Void) {
        self.glyph = glyph
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { action() }
    }

    override func accessibilityPerformPress() -> Bool { action(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = pressed ? 0.32 : hovering ? 0.22 : 0.12
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = glyph as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + 0.5),
                  withAttributes: attrs)
    }
}

extension NSMenuItem {
    static func stepper(title: String, value: String, onStep: @escaping (Int) -> String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = StepperMenuItemView(title: title, value: value, onStep: onStep)
        return item
    }
}

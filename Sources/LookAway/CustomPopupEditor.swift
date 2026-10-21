import AppKit
import SwiftUI

enum EditorSection: Int, CaseIterable {
    case title, message, icon, color, interval

    var isText: Bool { self == .title || self == .message }
}

final class PopupEditorModel: ObservableObject {
    @Published var draft: CustomPopup
    @Published var section: EditorSection = .title
    let isNew: Bool

    init(popup: CustomPopup?) {
        draft = popup ?? .draft()
        isNew = popup == nil
    }

    var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Tab / arrows: move between rows, wrapping around.
    func move(_ delta: Int) {
        let all = EditorSection.allCases
        section = all[(section.rawValue + delta + all.count) % all.count]
    }

    /// ←/→ on the icon, colour and interval rows.
    func adjust(_ delta: Int, big: Bool) {
        switch section {
        case .icon:
            let symbols = CustomPopup.symbols
            let i = symbols.firstIndex(of: draft.symbol) ?? 0
            draft.symbol = symbols[(i + delta + symbols.count) % symbols.count]
        case .color:
            let n = CustomPopup.palettes.count
            draft.colorIndex = (draft.colorIndex + delta + n) % n
        case .interval:
            setInterval(draft.intervalMinutes + delta * (big ? 30 : 5))
        case .title, .message:
            return
        }
        TickFeedback.shared.tick()
    }

    func setInterval(_ minutes: Int) {
        let r = CustomPopup.intervalRange
        draft.intervalMinutes = min(max(minutes, r.lowerBound), r.upperBound)
    }
}

struct PopupEditorView: View {
    @ObservedObject var model: PopupEditorModel
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focus: EditorSection?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B0A24, opacity: 0.25), Color(hex: 0x2B1F86, opacity: 0.2)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }

            VStack(spacing: 22) {
                Text(model.isNew ? "New custom popup" : "Edit popup")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                PopupPreview(popup: model.draft)

                VStack(spacing: 8) {
                    row(.title, "Title") {
                        TextField("Stand up and stretch", text: $model.draft.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                            .focused($focus, equals: .title)
                    }
                    row(.message, "Message") {
                        TextField("Optional, e.g. Roll your shoulders a few times.", text: $model.draft.message)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($focus, equals: .message)
                    }
                    row(.icon, "Icon") { iconPicker }
                    row(.color, "Colour") { colorPicker }
                    row(.interval, "Every") { intervalPicker }
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        HStack(spacing: 8) { Text("Cancel"); KeyCap("esc") }
                    }
                    .buttonStyle(PillButtonStyle())
                    Button(action: onSave) {
                        HStack(spacing: 8) { Text(model.isNew ? "Add popup" : "Save"); KeyCap("↩") }
                    }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .disabled(!model.canSave)
                    .opacity(model.canSave ? 1 : 0.45)
                }
                .padding(.top, 4)

                HStack(spacing: 14) {
                    hint(["tab"], "or"); hint(["↑", "↓"], "move")
                    hint(["←", "→"], "change"); hint(["⇧"], "bigger steps")
                }
            }
            .frame(width: 640)
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: model.section) { section in
            focus = section.isText ? section : nil
        }
        .onChange(of: focus) { field in
            if let field { model.section = field }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = .title }
        }
    }

    // MARK: Rows

    private func row<Content: View>(_ section: EditorSection, _ label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        let selected = model.section == section
        return HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(selected ? 0.75 : 0.45))
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(selected ? 0.09 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.pink, Palette.peach],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(0.08)),
                          lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { model.section = section }
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var iconPicker: some View {
        HStack(spacing: 5) {
            ForEach(CustomPopup.symbols, id: \.self) { symbol in
                let on = model.draft.symbol == symbol
                ZStack {
                    Circle().fill(on
                                  ? AnyShapeStyle(LinearGradient(colors: model.draft.colors,
                                                                 startPoint: .bottomLeading, endPoint: .topTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.06)))
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.7))
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .onTapGesture {
                    model.draft.symbol = symbol
                    model.section = .icon
                }
            }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(CustomPopup.palettes.indices, id: \.self) { i in
                let on = model.draft.colorIndex == i
                Circle()
                    .fill(LinearGradient(colors: CustomPopup.palettes[i].colors,
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0.9 : 0), lineWidth: 2))
                    .contentShape(Circle())
                    .onTapGesture {
                        model.draft.colorIndex = i
                        model.section = .color
                    }
                    .help(CustomPopup.palettes[i].name)
            }
        }
    }

    private var intervalPicker: some View {
        HStack(spacing: 10) {
            stepButton("−") { model.setInterval(model.draft.intervalMinutes - 5) }
            Text("\(model.draft.intervalMinutes) min")
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 72)
            stepButton("+") { model.setInterval(model.draft.intervalMinutes + 5) }
            Text("of screen time")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button {
            model.section = .interval
            action()
            TickFeedback.shared.tick()
        } label: {
            Text(glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func hint(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap($0) }
            Text(text).padding(.leading, 2)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.45))
    }
}

/// Live preview of the popup being edited, using the real nudge view.
private struct PopupPreview: View {
    let popup: CustomPopup

    var body: some View {
        var shown = popup
        if shown.title.trimmingCharacters(in: .whitespaces).isEmpty { shown.title = "Your reminder" }
        let model = NudgeModel()
        model.kind = .custom(shown)
        model.message = popup.message
        model.progress = 0.65
        return NudgeView(model: model, onLogWater: {}, onDismiss: {})
            .fixedSize()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: popup)
    }
}

private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen, keyboard-first editor for creating and editing custom popups.
final class PopupEditorController {
    var onSave: ((CustomPopup) -> Void)?
    /// Called whenever the editor closes, saved or not.
    var onClose: (() -> Void)?

    private var window: NSWindow?
    private var model: PopupEditorModel?
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { window != nil }

    func open(editing popup: CustomPopup? = nil) {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        let model = PopupEditorModel(popup: popup)
        self.model = model

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let screen = ReminderPanelController.activeScreen()
        let window = EditorWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: PopupEditorView(
            model: model,
            onSave: { [weak self] in self?.save() },
            onCancel: { [weak self] in self?.close() }
        ))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        window.contentView = effect
        window.setFrame(screen.frame, display: false)

        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let model else { return event }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: close()                                    // Esc
        case 36, 76: save()                                 // Return, Enter
        case 48: model.move(shift ? -1 : 1)                 // Tab / ⇧Tab
        case 126: model.move(-1)                            // ↑
        case 125: model.move(1)                             // ↓
        case 123 where !model.section.isText: model.adjust(-1, big: shift)   // ←
        case 124 where !model.section.isText: model.adjust(1, big: shift)    // →
        default: return event
        }
        return nil
    }

    private func save() {
        guard let model, model.canSave else { NSSound.beep(); return }
        var popup = model.draft
        popup.title = popup.title.trimmingCharacters(in: .whitespacesAndNewlines)
        popup.message = popup.message.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        onSave?(popup)
    }

    func close() {
        guard let window else { return }
        self.window = nil
        model = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        TickFeedback.shared.stop()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.previousApp?.activate(options: [])
            self?.previousApp = nil
        })
        onClose?()
    }
}

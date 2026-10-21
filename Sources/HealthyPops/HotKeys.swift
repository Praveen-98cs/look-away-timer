import Carbon.HIToolbox

/// System-wide shortcuts via Carbon hot keys. Unlike a global NSEvent monitor this needs
/// no Accessibility permission, and the key press is consumed instead of reaching the
/// app the user is typing in. Used only while the reminder pill is on screen.
final class HotKeys {
    static let controlOption = UInt32(controlKey | optionKey)

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    /// Shared across instances so hot key IDs never collide.
    private static var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            // Several HotKeys instances share the app target; let others handle keys that aren't ours.
            guard let action = hotKeys.actions[id.id] else { return OSStatus(eventNotHandledErr) }
            action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    func register(keyCode: Int, modifiers: UInt32 = controlOption, action: @escaping () -> Void) {
        let id = Self.nextID
        Self.nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4B_4157), id: id) // 'LKAW'
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        refs.append(ref)
        actions[id] = action
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }
}

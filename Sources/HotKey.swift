import Carbon.HIToolbox

/// System-wide shortcut via the Carbon hot-key API (needs no Accessibility permission).
/// Default: ⌃⌥P toggles the floating hourglass — handy right before you share your screen.
@MainActor
enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    static func register(keyCode: UInt32 = UInt32(kVK_ANSI_P), modifiers: UInt32 = UInt32(controlKey | optionKey),
                         action: @escaping () -> Void) {
        handler = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handler?() } }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x504F4D4F) /* 'POMO' */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

@preconcurrency import Carbon

@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.action?() }
            return noErr
        }, 1, &eventType, pointer, &handler)

        let identifier = EventHotKeyID(signature: fourCharacterCode("MYSS"), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}

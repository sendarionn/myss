@preconcurrency import Carbon

struct HotKeyConfiguration: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let `default` = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘K"
    )

    static var saved: HotKeyConfiguration {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "hotKey.keyCode") != nil else { return .default }
        return HotKeyConfiguration(
            keyCode: UInt32(defaults.integer(forKey: "hotKey.keyCode")),
            modifiers: UInt32(defaults.integer(forKey: "hotKey.modifiers")),
            displayName: defaults.string(forKey: "hotKey.displayName") ?? Self.default.displayName
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "hotKey.keyCode")
        defaults.set(Int(modifiers), forKey: "hotKey.modifiers")
        defaults.set(displayName, forKey: "hotKey.displayName")
    }
}

enum HotKeyRegistrationError: Error, Equatable {
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    @discardableResult
    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) -> Result<Void, HotKeyRegistrationError> {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    #if DEBUG
                    print("myss: global hotkey pressed")
                    #endif
                    manager.action?()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handler
        )
        guard handlerStatus == noErr else {
            print("myss: failed to install hotkey handler: \(handlerStatus)")
            self.action = nil
            return .failure(.handlerInstallationFailed(handlerStatus))
        }
        print("myss: hotkey event handler installed")

        let identifier = EventHotKeyID(signature: fourCharacterCode("MYSS"), id: 1)
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            print("myss: failed to register global hotkey: \(registrationStatus)")
            if let handler {
                RemoveEventHandler(handler)
                self.handler = nil
            }
            self.action = nil
            return .failure(.registrationFailed(registrationStatus))
        }
        print("myss: global hotkey registered: \(configuration.displayName)")
        return .success(())
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        action = nil
    }

    isolated deinit {
        unregister()
    }

    private func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}

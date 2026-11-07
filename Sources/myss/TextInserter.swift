@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class TextInserter {
    func insert(_ text: String, into context: CapturedContext) {
        context.sourceApplication?.activate()
        guard let element = context.targetElement else {
            copy(text)
            return
        }

        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        if status == .success, settable.boolValue,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return
        }

        copy(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AccessibilityContextReader {
    nonisolated static let maximumContextLength = 600

    func capture() -> CapturedContext {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return .empty }

        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        guard !isSecure(element) else { return .empty }

        let application = NSWorkspace.shared.frontmostApplication
        let value = stringAttribute(element, kAXValueAttribute)
        let range = rangeAttribute(element, kAXSelectedTextRangeAttribute)
        if let selected = stringAttribute(element, kAXSelectedTextAttribute), !selected.isEmpty {
            var surrounding = ""
            if let value, let range {
                surrounding = Self.contextAroundCursor(in: value, utf16Location: range.location)
            }
            if surrounding == selected.trimmingCharacters(in: .whitespacesAndNewlines) { surrounding = "" }
            return CapturedContext(
                text: limit(selected), surroundingText: surrounding, source: .selection,
                targetElement: element, sourceApplication: application
            )
        }

        guard let value, let range else {
            return CapturedContext(text: "", surroundingText: "", source: .none, targetElement: element, sourceApplication: application)
        }

        let context = Self.contextAroundCursor(in: value, utf16Location: range.location)
        return CapturedContext(
            text: context, surroundingText: "", source: context.isEmpty ? .none : .sentence,
            targetElement: element, sourceApplication: application
        )
    }

    nonisolated static func contextAroundCursor(in text: String, utf16Location: Int) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "" }
        let location = max(0, min(utf16Location, nsText.length))
        let separators = CharacterSet(charactersIn: "。！？\n")
        let before = nsText.substring(to: location) as NSString
        let startRange = before.rangeOfCharacter(from: separators, options: .backwards)
        let start = startRange.location == NSNotFound ? 0 : NSMaxRange(startRange)
        let afterRange = nsText.rangeOfCharacter(from: separators, range: NSRange(location: location, length: nsText.length - location))
        let end = afterRange.location == NSNotFound ? nsText.length : NSMaxRange(afterRange)
        let raw = nsText.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(raw.suffix(maximumContextLength))
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private func limit(_ text: String) -> String {
        String(text.prefix(Self.maximumContextLength))
    }
}

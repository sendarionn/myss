@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AccessibilityContextReader {
    nonisolated static let maximumSelectionLength = 600
    nonisolated static let maximumSurroundingLength = 400

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
        if let selected = stringAttribute(element, kAXSelectedTextAttribute),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let selectedText = String(selected.prefix(Self.maximumSelectionLength))
            var surrounding = ""
            if let value, let range {
                surrounding = Self.contextAroundCursor(in: value, utf16Location: range.location).text
            }
            if surrounding == selectedText.trimmingCharacters(in: .whitespacesAndNewlines) { surrounding = "" }
            return CapturedContext(
                selectedText: selectedText, surroundingText: surrounding, cursorOffset: nil,
                source: .selection, targetElement: element, sourceApplication: application
            )
        }

        guard let value, let range else {
            return CapturedContext(
                selectedText: "", surroundingText: "", cursorOffset: nil,
                source: .none, targetElement: element, sourceApplication: application
            )
        }

        let context = Self.contextAroundCursor(in: value, utf16Location: range.location)
        return CapturedContext(
            selectedText: "", surroundingText: context.text,
            cursorOffset: context.text.isEmpty ? nil : context.cursorOffset,
            source: context.text.isEmpty ? .none : .sentence,
            targetElement: element, sourceApplication: application
        )
    }

    /// カーソルを含む文と前後の文を取り出す　文書全体は返さない
    nonisolated static func contextAroundCursor(
        in text: String,
        utf16Location: Int,
        neighborSentences: Int = 1,
        maximumLength: Int = maximumSurroundingLength
    ) -> (text: String, cursorOffset: Int) {
        let nsText = text as NSString
        guard nsText.length > 0 else { return ("", 0) }
        let location = max(0, min(utf16Location, nsText.length))
        let separators = CharacterSet(charactersIn: "。！？\n")

        var start = location
        for index in 0...neighborSentences {
            let limit = index == 0 ? start : start - 1
            guard limit > 0 else { start = 0; break }
            let found = nsText.rangeOfCharacter(from: separators, options: .backwards, range: NSRange(location: 0, length: limit))
            start = found.location == NSNotFound ? 0 : NSMaxRange(found)
            if start == 0 { break }
        }

        var end = location
        for _ in 0...neighborSentences {
            guard end < nsText.length else { break }
            let found = nsText.rangeOfCharacter(from: separators, range: NSRange(location: end, length: nsText.length - end))
            end = found.location == NSNotFound ? nsText.length : NSMaxRange(found)
        }

        if end - start > maximumLength {
            let windowStart = max(start, min(location - maximumLength / 2, end - maximumLength))
            start = windowStart
            end = min(end, windowStart + maximumLength)
        }
        let window = nsText.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        let raw = nsText.substring(with: window) as NSString
        let leading = raw.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
        guard leading.location != NSNotFound else { return ("", 0) }
        let trimmed = (raw.substring(from: leading.location) as String).trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = location - window.location - leading.location
        return (trimmed, max(0, min(offset, (trimmed as NSString).length)))
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
}

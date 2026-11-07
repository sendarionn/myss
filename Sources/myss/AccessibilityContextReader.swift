@preconcurrency import AppKit
@preconcurrency import ApplicationServices

enum SelectionAcquisitionMethod: String {
    case selectedTextAttribute
    case selectedTextRangeAndValue
    case parameterizedRange
    case clipboard
}

struct SelectionResult {
    let text: String
    let range: CFRange?
    let method: SelectionAcquisitionMethod
}

@MainActor
final class AccessibilityContextReader {
    nonisolated static let maximumSelectionLength = 600
    nonisolated static let maximumSurroundingLength = 400
    /// AXValueが取れない場合に、parameterized APIで周辺文脈として読む前後の文字数
    nonisolated static let parameterizedWindowLength = 600

    private let clipboardReader = ClipboardSelectionReader()

    /// フォーカス要素取得 → secure判定 → 選択取得 → 周辺文脈取得の順に行う
    /// クリップボード方式を含むため、myssのパネルを前面に出す前に呼ぶ
    func capture() async -> CapturedContext {
        var log = ContextDebugLog()
        let application = NSWorkspace.shared.frontmostApplication
        guard let element = focusedElement() else {
            // フォーカス要素を公開しないアプリでは選択状態を確認できないため、⌘Cだけを試す
            log.add("focusedElement=unavailable")
            let copied = await clipboardReader.copySelection()
            log.add("clipboardFallback=\(copied == nil ? "failed" : "success")")
            defer { log.flush() }
            guard let copied, let text = Self.limitedSelection(copied) else { return .empty }
            log.add("selectionMethod=clipboard selectedLength=\((text as NSString).length)")
            return CapturedContext(
                selectedText: text, surroundingText: "", cursorOffset: nil,
                source: .selection, targetElement: nil, sourceApplication: application
            )
        }
        defer { log.flush() }
        log.add("role=\(stringAttribute(element, kAXRoleAttribute) ?? "unknown")")
        guard !isSecure(element) else {
            log.add("secure=true")
            return .empty
        }
        log.addAttributeNames(of: element)

        let value = stringAttribute(element, kAXValueAttribute)
        let range = rangeAttribute(element, kAXSelectedTextRangeAttribute)
        log.add(range.map { "selectedRange=location:\($0.location) length:\($0.length)" } ?? "selectedRange=unavailable")
        log.add("AXValue=\(value == nil ? "unavailable" : "available")")

        var selection = selectedText(from: element, value: value, range: range, log: &log)
        if selection == nil, range == nil {
            // 選択範囲を公開していないアプリだけ⌘Cを試す　範囲が取得でき長さ0なら選択なしとして扱う
            let copied = await clipboardReader.copySelection()
            log.add("clipboardFallback=\(copied == nil ? "failed" : "success")")
            if let copied, let text = Self.limitedSelection(copied) {
                selection = SelectionResult(text: text, range: nil, method: .clipboard)
            }
        }

        let context = surroundingContext(of: element, value: value, range: range)
        if let selection {
            log.add("selectionMethod=\(selection.method.rawValue) selectedLength=\((selection.text as NSString).length)")
            var surrounding = context?.text ?? ""
            if surrounding == selection.text.trimmingCharacters(in: .whitespacesAndNewlines) { surrounding = "" }
            log.add("surroundingLength=\((surrounding as NSString).length)")
            return CapturedContext(
                selectedText: selection.text, surroundingText: surrounding, cursorOffset: nil,
                source: .selection, targetElement: element, sourceApplication: application
            )
        }

        log.add("selectionMethod=none surroundingLength=\(((context?.text ?? "") as NSString).length)")
        guard let context, !context.text.isEmpty else {
            return CapturedContext(
                selectedText: "", surroundingText: "", cursorOffset: nil,
                source: .none, targetElement: element, sourceApplication: application
            )
        }
        return CapturedContext(
            selectedText: "", surroundingText: context.text, cursorOffset: context.cursorOffset,
            source: .sentence, targetElement: element, sourceApplication: application
        )
    }

    /// Accessibility APIで取得できる選択文字列を優先順に試す
    private func selectedText(from element: AXUIElement, value: String?, range: CFRange?, log: inout ContextDebugLog) -> SelectionResult? {
        if let selected = stringAttribute(element, kAXSelectedTextAttribute), let text = Self.limitedSelection(selected) {
            log.add("AXSelectedText=success")
            return SelectionResult(text: text, range: range, method: .selectedTextAttribute)
        }
        log.add("AXSelectedText=unavailable")
        guard let range, range.length > 0 else { return nil }

        if let value {
            if let selected = Self.substring(of: value, range: range), let text = Self.limitedSelection(selected) {
                log.add("rangeValueFallback=success")
                return SelectionResult(text: text, range: range, method: .selectedTextRangeAndValue)
            }
            log.add("rangeValueFallback=failed")
        }

        if let selected = stringForRange(element, range: range), let text = Self.limitedSelection(selected) {
            log.add("parameterizedRange=success")
            return SelectionResult(text: text, range: range, method: .parameterizedRange)
        }
        log.add("parameterizedRange=unsupported")
        return nil
    }

    /// AXValueと選択範囲から周辺文脈を作る　AXValueがなければparameterized APIで範囲の前後だけを読む
    private func surroundingContext(of element: AXUIElement, value: String?, range: CFRange?) -> (text: String, cursorOffset: Int)? {
        guard let range else { return nil }
        if let value {
            return Self.contextAroundCursor(in: value, utf16Location: range.location)
        }
        let window = Self.parameterizedWindowLength
        let start = max(0, range.location - window)
        var end = range.location + max(range.length, 0) + window
        if let count = intAttribute(element, kAXNumberOfCharactersAttribute) { end = min(end, count) }
        let candidates = [CFRange(location: start, length: end - start), CFRange(location: start, length: range.location - start)]
        for candidate in candidates where candidate.length > 0 {
            if let text = stringForRange(element, range: candidate) {
                return Self.contextAroundCursor(in: text, utf16Location: range.location - start)
            }
        }
        return nil
    }

    /// UTF-16の範囲で切り出す　範囲外や長さ0ならnil
    nonisolated static func substring(of value: String, range: CFRange) -> String? {
        let nsValue = value as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= nsValue.length,
              range.length <= nsValue.length - range.location
        else { return nil }
        return nsValue.substring(with: NSRange(location: range.location, length: range.length))
    }

    /// 空白だけの選択を除外し、既存の上限文字数に収める
    nonisolated static func limitedSelection(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(text.prefix(maximumSelectionLength))
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

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focusedValue, to: AXUIElement.self)
    }

    private func stringForRange(_ element: AXUIElement, range: CFRange) -> String? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value
        ) == .success,
              let string = value as? String,
              !string.isEmpty
        else { return nil }
        return string
    }

    private func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
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

/// Debug buildだけで取得経路を出力する　選択文字列、周辺文章、クリップボード内容は記録しない
struct ContextDebugLog {
    private var lines: [String] = []

    mutating func add(_ line: @autoclosure () -> String) {
        #if DEBUG
        lines.append(line())
        #endif
    }

    /// MYSS_AX_ATTRIBUTES=1の場合だけ、要素が公開している属性名を記録する
    mutating func addAttributeNames(of element: AXUIElement) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MYSS_AX_ATTRIBUTES"] == "1" else { return }
        var names: CFArray?
        if AXUIElementCopyAttributeNames(element, &names) == .success, let names = names as? [String] {
            lines.append("attributes=\(names.sorted().joined(separator: ","))")
        }
        var parameterized: CFArray?
        if AXUIElementCopyParameterizedAttributeNames(element, &parameterized) == .success,
           let parameterized = parameterized as? [String] {
            lines.append("parameterizedAttributes=\(parameterized.sorted().joined(separator: ","))")
        }
        #endif
    }

    func flush() {
        #if DEBUG
        guard !lines.isEmpty else { return }
        print((["[myss][context]"] + lines).joined(separator: "\n"))
        #endif
    }
}

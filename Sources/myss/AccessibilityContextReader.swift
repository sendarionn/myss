@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Carbon

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
        let application = NSWorkspace.shared.frontmostApplication
        var diagnostics = SelectionDiagnostics(sourceApp: application?.localizedName ?? "unknown")
        defer { SelectionDiagnosticsStore.shared.record(diagnostics) }

        guard !IsSecureEventInputEnabled() else {
            diagnostics.secure = true
            return .empty
        }
        let element = focusedElement()
        if let element {
            diagnostics.role = stringAttribute(element, kAXRoleAttribute) ?? "unknown"
            guard !isSecure(element) else {
                diagnostics.secure = true
                return .empty
            }
            diagnostics.addAttributeNames(of: element)
        }

        let value = element.flatMap { stringAttribute($0, kAXValueAttribute) }
        let range = element.flatMap { rangeAttribute($0, kAXSelectedTextRangeAttribute) }
        diagnostics.selectedRange = range.map { "location=\($0.location) length=\($0.length)" } ?? "unavailable"
        diagnostics.axValue = value == nil ? "unavailable" : "available"

        var selection = element.flatMap { selectedText(from: $0, value: value, range: range, diagnostics: &diagnostics) }
        if Self.needsClipboardFallback(selection: selection) {
            // 画面上の選択とフォーカス要素の範囲が一致しないアプリがあるため、範囲が長さ0でも⌘Cを試す
            // changeCountが変わらなければ失敗とし、古いクリップボードの内容は使わない
            let copied = await clipboardReader.copySelection()
            diagnostics.clipboardFallback = copied == nil ? "failed" : "success"
            if let copied, let text = Self.limitedSelection(copied) {
                selection = SelectionResult(text: text, range: nil, method: .clipboard)
            }
        }

        let context = element.flatMap { surroundingContext(of: $0, value: value, range: range) }
        if let selection {
            diagnostics.selectionMethod = selection.method.rawValue
            diagnostics.selectedLength = (selection.text as NSString).length
            var surrounding = context?.text ?? ""
            if surrounding == selection.text.trimmingCharacters(in: .whitespacesAndNewlines) { surrounding = "" }
            diagnostics.surroundingLength = (surrounding as NSString).length
            return CapturedContext(
                selectedText: selection.text, surroundingText: surrounding, cursorOffset: nil,
                source: .selection, targetElement: element, sourceApplication: application
            )
        }

        diagnostics.surroundingLength = ((context?.text ?? "") as NSString).length
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

    /// Accessibility APIで選択を確認できなければ、範囲の状態に関係なく⌘Cを試す
    nonisolated static func needsClipboardFallback(selection: SelectionResult?) -> Bool {
        selection == nil
    }

    /// Accessibility APIで取得できる選択文字列を優先順に試す
    private func selectedText(
        from element: AXUIElement, value: String?, range: CFRange?, diagnostics: inout SelectionDiagnostics
    ) -> SelectionResult? {
        if let selected = stringAttribute(element, kAXSelectedTextAttribute), let text = Self.limitedSelection(selected) {
            diagnostics.axSelectedText = "success"
            return SelectionResult(text: text, range: range, method: .selectedTextAttribute)
        }
        diagnostics.axSelectedText = "failed"
        guard let range, range.length > 0 else { return nil }

        if let value {
            if let selected = Self.substring(of: value, range: range), let text = Self.limitedSelection(selected) {
                diagnostics.rangeAndValue = "success"
                return SelectionResult(text: text, range: range, method: .selectedTextRangeAndValue)
            }
            diagnostics.rangeAndValue = "failed"
        }

        if let selected = stringForRange(element, range: range), let text = Self.limitedSelection(selected) {
            diagnostics.parameterizedRange = "success"
            return SelectionResult(text: text, range: range, method: .parameterizedRange)
        }
        diagnostics.parameterizedRange = "failed"
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

/// 直近の選択取得結果　選択文字列、周辺文章、クリップボード内容は保持しない
struct SelectionDiagnostics: Equatable {
    var date = Date()
    var sourceApp: String
    var role = "unavailable"
    var secure = false
    var selectedRange = "not checked"
    var axSelectedText = "not checked"
    var axValue = "not checked"
    var rangeAndValue = "not checked"
    var parameterizedRange = "not checked"
    var clipboardFallback = "not run"
    var selectionMethod = "none"
    var selectedLength = 0
    var surroundingLength = 0
    var attributeNames: String?

    var lines: [(label: String, value: String)] {
        var lines: [(String, String)] = [
            ("Source app", sourceApp),
            ("Focused role", role),
            ("Secure input", secure ? "yes" : "no"),
            ("Selected range", selectedRange),
            ("AXSelectedText", axSelectedText),
            ("AXValue", axValue),
            ("Range + value", rangeAndValue),
            ("Parameterized range", parameterizedRange),
            ("Clipboard fallback", clipboardFallback),
            ("Selection method", selectionMethod),
            ("Selected length", "\(selectedLength)"),
            ("Surrounding length", "\(surroundingLength)")
        ]
        if let attributeNames { lines.append(("Attributes", attributeNames)) }
        return lines
    }

    /// MYSS_AX_ATTRIBUTES=1の場合だけ、要素が公開している属性名を記録する
    mutating func addAttributeNames(of element: AXUIElement) {
        guard ProcessInfo.processInfo.environment["MYSS_AX_ATTRIBUTES"] == "1" else { return }
        var names: CFArray?
        var parameterized: CFArray?
        _ = AXUIElementCopyAttributeNames(element, &names)
        _ = AXUIElementCopyParameterizedAttributeNames(element, &parameterized)
        let all = ((names as? [String]) ?? []) + ((parameterized as? [String]) ?? []).map { "(param)\($0)" }
        attributeNames = all.sorted().joined(separator: ",")
    }
}

@MainActor
final class SelectionDiagnosticsStore: ObservableObject {
    static let shared = SelectionDiagnosticsStore()
    @Published private(set) var last: SelectionDiagnostics?

    func record(_ diagnostics: SelectionDiagnostics) {
        last = diagnostics
        #if DEBUG
        print((["[myss][context]"] + diagnostics.lines.map { "\($0.label)=\($0.value)" }).joined(separator: "\n"))
        #endif
    }
}

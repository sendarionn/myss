@preconcurrency import AppKit
@preconcurrency import Carbon
import Foundation

/// Accessibility APIで選択文字列を取得できない場合の最終手段として、⌘Cで選択文字列を取得する
/// 既存のクリップボードは全形式を退避し、取得後に復元する
@MainActor
final class ClipboardSelectionReader {
    static let pollInterval: Duration = .milliseconds(15)
    static let timeout: Duration = .milliseconds(220)
    private static let cKeyCode: CGKeyCode = 8

    private let pasteboard: NSPasteboard
    private var isRunning = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// 元アプリが前面にある状態で呼ぶ　myssのパネルを表示する前に実行すること
    func copySelection() async -> String? {
        // 連続起動時に⌘C処理を重ねない　パスワード入力中（Secure Event Input）は実行しない
        guard !isRunning, !IsSecureEventInputEnabled() else { return nil }
        isRunning = true
        defer { isRunning = false }

        let snapshot = PasteboardSnapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount
        sendCopyShortcut()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while pasteboard.changeCount == initialChangeCount, clock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
        }
        guard pasteboard.changeCount != initialChangeCount else { return nil }

        let copied = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return copied
    }

    private func sendCopyShortcut() {
        // ショートカットの修飾キーを押したままでも⌘Cだけが届くよう、独立したイベントソースを使う
        let source = CGEventSource(stateID: .privateState)
        let commandKey = CGKeyCode(kVK_Command)
        let events = [
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: false),
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        ]
        for (index, event) in events.enumerated() {
            event?.flags = index == 3 ? [] : .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// クリップボードの全項目と全形式のデータ
struct PasteboardSnapshot {
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.compactMap { entries -> NSPasteboardItem? in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        guard !restored.isEmpty else { return }
        if !pasteboard.writeObjects(restored) {
            #if DEBUG
            print("[myss][context] clipboardRestore=failed")
            #endif
        }
    }
}

@preconcurrency import ApplicationServices
@preconcurrency import Carbon
import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let myssHotKeyDidChange = Notification.Name("myssHotKeyDidChange")
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotKey = HotKeyConfiguration.saved
    @Published var hotKeyError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var loginItemError: String?

    func updateHotKey(_ configuration: HotKeyConfiguration) {
        hotKey = configuration
        hotKeyError = nil
        NotificationCenter.default.post(name: .myssHotKeyDidChange, object: configuration)
    }

    func setHotKeyResult(_ result: Result<Void, HotKeyRegistrationError>) {
        switch result {
        case .success:
            hotKey.save()
            hotKeyError = nil
        case let .failure(error):
            hotKeyError = "登録できませんでした　\(error)"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            loginItemError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = error.localizedDescription
        }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }
}

enum PrivacyNotice {
    static let text = "myssは回答生成のため、選択文字列や周辺文章を設定されたAIサービスへ送信します\nパスワード欄は読み取りません"
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var assistant = LanguageAssistant.shared
    @State private var showsTranscript = false

    var body: some View {
        Form {
            Section("一般") {
                Toggle("Macへのログイン時にmyssを起動", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.loginItemError { Text(error).foregroundStyle(.red).font(.caption) }
            }

            Section("ショートカット") {
                LabeledContent("myssを開く") {
                    HotKeyRecorder(configuration: settings.hotKey) { settings.updateHotKey($0) }
                        .frame(width: 150, height: 28)
                }
                if let error = settings.hotKeyError { Text(error).foregroundStyle(.red).font(.caption) }
            }

            Section("AI") {
                LabeledContent("Provider", value: assistant.providerKind.label)
                APIKeyForm(assistant: assistant)
            }

            Section("権限") {
                StatusRow(
                    label: "アクセシビリティ",
                    value: settings.accessibilityGranted ? "許可済み" : "未許可",
                    success: settings.accessibilityGranted
                )
                if !settings.accessibilityGranted {
                    Button("アクセシビリティを許可") { settings.requestAccessibility() }
                }
            }

            Section("詳細") {
                LabeledContent("バージョン", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "開発版")
                LabeledContent("プライバシー") {
                    Text(PrivacyNotice.text).font(.caption).multilineTextAlignment(.trailing)
                }
                Button(showsTranscript ? "送信内容を隠す" : "最後にAIへ送信した内容を表示") { showsTranscript.toggle() }
                    .disabled(assistant.lastSentTranscript == nil)
                if showsTranscript, let transcript = assistant.lastSentTranscript {
                    Text(transcript)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { settings.refreshPermissions() }
    }
}

struct APIKeyForm: View {
    @ObservedObject var assistant: LanguageAssistant
    @State private var draft = ""

    var body: some View {
        LabeledContent("API Key") {
            HStack {
                Text(assistant.hasAPIKey ? "保存済み" : "未設定").foregroundStyle(.secondary)
                SecureField("sk-…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(save)
                Button("保存", action: save).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        LabeledContent("接続状態") {
            HStack {
                connectionLabel
                if assistant.hasAPIKey {
                    Button("接続確認") { Task { await assistant.verifyConnection() } }
                        .disabled(assistant.connectionState == .checking)
                    Button("削除", role: .destructive) { assistant.deleteAPIKey() }
                }
            }
        }
    }

    @ViewBuilder private var connectionLabel: some View {
        switch assistant.connectionState {
        case .unknown:
            Text(assistant.hasAPIKey ? "未確認" : "未設定").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
        case .connected:
            Label("接続済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
        }
    }

    private func save() {
        let value = draft
        draft = ""
        Task { await assistant.saveAPIKey(value) }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let success: Bool
    var body: some View {
        LabeledContent(label) {
            Label(value, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(success ? .green : .secondary)
        }
    }
}

private struct HotKeyRecorder: NSViewRepresentable {
    let configuration: HotKeyConfiguration
    let onChange: (HotKeyConfiguration) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.configuration = configuration
        button.onChange = onChange
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.configuration = configuration
        button.onChange = onChange
        if !button.isRecording { button.title = configuration.displayName }
    }
}

private final class RecorderButton: NSButton {
    var configuration = HotKeyConfiguration.default
    var onChange: ((HotKeyConfiguration) -> Void)?
    var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "キーを入力"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        let display = modifierDisplay(flags) + key
        isRecording = false
        onChange?(HotKeyConfiguration(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, displayName: display))
    }

    private func modifierDisplay(_ flags: NSEvent.ModifierFlags) -> String {
        var value = ""
        if flags.contains(.control) { value += "⌃" }
        if flags.contains(.option) { value += "⌥" }
        if flags.contains(.shift) { value += "⇧" }
        if flags.contains(.command) { value += "⌘" }
        return value
    }
}

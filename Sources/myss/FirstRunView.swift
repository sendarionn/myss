import SwiftUI

struct FirstRunView: View {
    static let completedKey = "firstRunCompleted"

    @ObservedObject var settings: SettingsModel
    @ObservedObject private var assistant = LanguageAssistant.shared
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("myssの準備").font(.title2).fontWeight(.semibold)

            Form {
                Section("アクセシビリティ") {
                    if settings.accessibilityGranted {
                        Label("許可済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("許可する") { settings.requestAccessibility() }
                    }
                }
                Section("AI") {
                    LabeledContent("Provider", value: assistant.providerKind.label)
                    APIKeyForm(assistant: assistant)
                }
                Section {
                    LabeledContent("ショートカット", value: settings.hotKey.displayName)
                } footer: {
                    Text(PrivacyNotice.text).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("開始") {
                    UserDefaults.standard.set(true, forKey: Self.completedKey)
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!assistant.hasAPIKey)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { settings.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshPermissions()
        }
    }
}

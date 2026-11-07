import SwiftUI

struct FirstRunView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var setup = SetupManager.shared
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("myssの準備").font(.title2).fontWeight(.semibold)

            GroupBox("アクセシビリティ") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("入力中の文章を取得し、検索した語をカーソル位置へ挿入するために使用します\nパスワード欄は読み取りません")
                    if settings.accessibilityGranted {
                        Label("許可済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("アクセシビリティを許可") { settings.requestAccessibility() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("検索データ") {
                VStack(alignment: .leading, spacing: 10) {
                    if setup.isRunning {
                        ProgressView(value: setup.progress)
                        Text(setup.stage.rawValue).foregroundStyle(.secondary)
                    } else if setup.stage == .ready {
                        Label("準備済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("検索データを準備") { setup.prepare() }
                    }
                    if let error = setup.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Text("ショートカット　\(settings.hotKey.displayName)").foregroundStyle(.secondary)
                Spacer()
                Button("myssを使う") { onComplete() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.stage != .ready)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear { settings.refreshPermissions() }
    }
}

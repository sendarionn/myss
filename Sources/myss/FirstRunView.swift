import SwiftUI

struct FirstRunView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var setup = SetupManager.shared
    let onComplete: () -> Void
    @State private var showsDetails = false

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
                    ForEach(SetupStep.allCases) { step in
                        SetupStepRow(label: step.rawValue, state: setup.stepStates[step] ?? .pending)
                    }
                    if setup.isRunning { ProgressView(value: setup.progress) }
                    if let error = setup.errorMessage {
                        Text(error).foregroundStyle(.red)
                        HStack {
                            Button("再試行") { setup.retry() }
                            Button(showsDetails ? "詳細を隠す" : "詳細を表示") { showsDetails.toggle() }
                        }
                    } else if setup.stage != .ready, !setup.isRunning {
                        Button("検索データを準備") { setup.prepare() }
                    }
                    if showsDetails, let details = setup.errorDetails {
                        ScrollView { Text(details).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            .frame(maxHeight: 120)
                    }
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

struct SetupStepRow: View {
    let label: String
    let state: SetupStepState

    var body: some View {
        Label(label, systemImage: symbol)
            .foregroundStyle(state == .failed ? .red : state == .complete ? .green : .primary)
    }

    private var symbol: String {
        switch state {
        case .pending: "circle"
        case .running: "circle.fill"
        case .complete: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }
}

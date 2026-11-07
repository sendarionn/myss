import SwiftUI

struct AssistantPanelView: View {
    @ObservedObject var model: AssistantViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 600, height: 460)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onMoveCommand { direction in
            if direction == .up { model.moveSelection(-1) }
            if direction == .down { model.moveSelection(1) }
        }
        .onExitCommand { model.onDismiss?() }
        .background {
            Button("コピー") { model.copySelection() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
                TextField(model.context.isEmpty ? "語や表現について入力" : "追加の指示", text: $model.instruction)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($inputFocused)
                    .onSubmit { model.primaryAction() }
                    .onChange(of: model.instruction) { _, _ in model.instructionChanged() }
                if model.isLoading && model.response != nil { ProgressView().controlSize(.small) }
            }
            if !model.subject.isEmpty {
                Text(model.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if let message = model.errorMessage {
            VStack(spacing: 12) {
                ContentUnavailableView("回答できません", systemImage: "exclamationmark.bubble", description: Text(message))
                if model.error == .missingAPIKey || model.error == .invalidAPIKey {
                    Button("設定を開く") { model.onOpenSettings?() }
                } else {
                    Button("再試行") { model.retry() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let response = model.response {
            responseView(response)
        } else if model.isLoading {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("考えています…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("文章を選択するか入力してください", systemImage: "text.cursor")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func responseView(_ response: LanguageResponse) -> some View {
        ScrollViewReader { proxy in
            List {
                if !response.summary.isEmpty {
                    Text(response.summary)
                        .font(.system(size: response.candidates.isEmpty ? 15 : 13))
                        .foregroundStyle(response.candidates.isEmpty ? .primary : .secondary)
                        .textSelection(.enabled)
                        .listRowInsets(.init(top: 10, leading: 14, bottom: 10, trailing: 14))
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(response.candidates.enumerated()), id: \.element.id) { index, candidate in
                    CandidateRow(candidate: candidate, isSelected: index == model.selectedIndex)
                        .id(candidate.id)
                        .listRowInsets(.init(top: 8, leading: 14, bottom: 8, trailing: 14))
                        .listRowBackground(index == model.selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.insert(candidate) }
                        .onTapGesture { model.selectedIndex = index }
                        .contextMenu {
                            Button("挿入") { model.insert(candidate) }
                            Button("コピー") { model.copy(candidate) }
                        }
                }
            }
            .listStyle(.plain)
            .onChange(of: model.selectedIndex) { _, index in
                guard response.candidates.indices.contains(index) else { return }
                proxy.scrollTo(response.candidates[index].id)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.context.source.rawValue)
            Spacer()
            Text(model.candidates.isEmpty
                 ? "⌘↩ コピー   esc 閉じる"
                 : "↕ 選択   ↩ 挿入   ⌘↩ コピー   esc 閉じる")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}

private struct CandidateRow: View {
    let candidate: LanguageCandidate
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(candidate.text).font(.system(size: 16, weight: isSelected ? .semibold : .medium))
            if !candidate.explanation.isEmpty {
                Text(candidate.explanation).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

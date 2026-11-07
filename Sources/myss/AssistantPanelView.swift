import SwiftUI

struct AssistantPanelView: View {
    @ObservedObject var model: AssistantViewModel
    @ObservedObject private var historyStore: SearchHistoryStore
    @FocusState private var inputFocused: Bool

    init(model: AssistantViewModel) {
        self.model = model
        historyStore = model.historyStore
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            content
        }
        .frame(width: 600, height: 440)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onMoveCommand { direction in
            if direction == .up { model.moveSelection(-1) }
            if direction == .down { model.moveSelection(1) }
        }
        .onExitCommand { model.dismiss() }
        .background {
            Button("コピー") { model.copySelection() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("入力…", text: $model.queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($inputFocused)
                    .onSubmit { model.primaryAction() }
                    .onChange(of: model.queryText) { _, _ in model.queryChanged() }
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            if !model.accessibilityTrusted {
                HStack(spacing: 8) {
                    Label("アクセシビリティ権限がありません　設定からmyssを許可してください", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("設定を開く") { model.onOpenSettings?() }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if model.isShowingHistory {
            historyList
        } else if let message = model.errorMessage {
            VStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.secondary)
                if case .modelUnavailable = model.error {
                    Button("設定を開く") { model.onOpenSettings?() }
                } else {
                    Button("再試行") { model.retry() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let response = model.response {
            responseView(response)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            List(Array(historyStore.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Image(systemName: "clock").foregroundStyle(.tertiary)
                    Text(item.query).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(item.createdAt, format: .relative(presentation: .numeric))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .id(item.id)
                .listRowInsets(.init(top: 6, leading: 14, bottom: 6, trailing: 14))
                .listRowBackground(index == model.selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { model.openHistory(item) }
            }
            .listStyle(.plain)
            .onChange(of: model.selectedIndex) { _, index in
                guard historyStore.items.indices.contains(index) else { return }
                proxy.scrollTo(historyStore.items[index].id)
            }
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

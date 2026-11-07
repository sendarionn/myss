import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var model: SearchViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("意味や語を入力", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($inputFocused)
                    .onSubmit { model.insertSelection() }
                    .onChange(of: model.query) { _, _ in model.queryChanged() }
                Picker("検索方向", selection: Binding(
                    get: { model.direction },
                    set: { model.setDirection($0) }
                )) {
                    ForEach(SearchDirection.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 112)
            }
            .padding(14)

            Divider()

            if model.results.isEmpty {
                ContentUnavailableView("候補なし", systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == model.selectedIndex)
                            .id(result.id)
                            .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowBackground(index == model.selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedIndex = index }
                            .onTapGesture(count: 2) { model.insertSelection() }
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedIndex) { _, index in
                        guard model.results.indices.contains(index) else { return }
                        proxy.scrollTo(model.results[index].id)
                    }
                }
            }

            Divider()
            HStack {
                Text(model.contextSource.rawValue)
                Spacer()
                Text("↕ 選択   ↩ 挿入   ⌘↩ コピー   esc 閉じる")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .frame(width: 620, height: 480)
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
}

private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.entry.word)
                .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
            Text(result.entry.summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var model: SearchViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 680, height: 560)
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("意味や語を入力", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($inputFocused)
                .onSubmit { model.primaryAction() }
                .onChange(of: model.query) { _, _ in model.queryChanged() }
            if model.isSearching { ProgressView().controlSize(.small) }
            Picker("検索方向", selection: Binding(get: { model.direction }, set: { model.setDirection($0) })) {
                ForEach(SearchDirection.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 112)
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if let message = model.statusMessage {
            ContentUnavailableView("検索できません", systemImage: "exclamationmark.magnifyingglass", description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isSearching && model.results.isEmpty {
            ContentUnavailableView("myssを準備しています", systemImage: "hourglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty {
            ContentUnavailableView("語または意味を入力", systemImage: "text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.direction == .wordToMeaning {
            meaningDetail
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            List(Array(model.results.enumerated()), id: \.element.id) { index, sense in
                ResultRow(sense: sense, isSelected: index == model.selectedIndex)
                    .id(sense.id)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(index == model.selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedIndex = index }
                    .onTapGesture(count: 2) { model.primaryAction() }
            }
            .listStyle(.plain)
            .onChange(of: model.selectedIndex) { _, index in
                guard model.results.indices.contains(index) else { return }
                proxy.scrollTo(model.results[index].id)
            }
        }
    }

    private var meaningDetail: some View {
        HSplitView {
            List(Array(model.results.enumerated()), id: \.element.id) { index, sense in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sense.headword).fontWeight(index == model.selectedIndex ? .semibold : .regular)
                    if let part = partOfSpeechLabel(sense.partOfSpeech) {
                        Text(part).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectedIndex = index }
            }
            .frame(minWidth: 150, idealWidth: 180)

            if let sense = model.selectedSense {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(sense.headword).font(.title2).fontWeight(.semibold)
                        DetailSection(title: "要約", values: [sense.summary])
                        if !sense.aliases.isEmpty {
                            DetailSection(title: "同義語", values: [sense.aliases.prefix(12).joined(separator: "、")])
                        }
                        if !sense.examples.isEmpty {
                            DetailSection(title: "用例", values: Array(sense.examples.prefix(3)))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("典拠").font(.caption).foregroundStyle(.secondary)
                            ForEach(sense.sources) { source in
                                if let url = source.url { Link(source.name, destination: url) }
                                else { Text(source.name).fontWeight(.medium) }
                                Text(source.text).font(.callout)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 400)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.contextSource.rawValue)
            Spacer()
            Text(model.direction == .meaningToWord
                 ? "↕ 選択   ↩ 挿入   ⌘↩ コピー   esc 閉じる"
                 : "↕ 語義選択   ⌘↩ コピー   esc 閉じる")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private func partOfSpeechLabel(_ value: String?) -> String? {
        switch value {
        case "n": "名詞"
        case "v": "動詞"
        case "a": "形容詞"
        case "r": "副詞"
        default: value
        }
    }
}

private struct DetailSection: View {
    let title: String
    let values: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(values, id: \.self) { Text($0) }
        }
    }
}

private struct ResultRow: View {
    let sense: LexicalSense
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sense.headword).font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                if let part = sense.partOfSpeech { Text(part).font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(sense.summary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

import Foundation

struct SemanticSearchEngine: Sendable {
    func direction(for text: String) -> SearchDirection {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isKnownWord = Lexicon.entries.contains { entry in
            entry.word == normalized || entry.aliases.contains(normalized)
        }
        if isKnownWord || (normalized.count <= 8 && !normalized.contains(where: "。！？、\n".contains)) {
            return .wordToMeaning
        }
        return .meaningToWord
    }

    func search(query: String, direction: SearchDirection, limit: Int = 10) -> [SearchResult] {
        let query = normalize(query)
        guard !query.isEmpty else { return [] }

        return Lexicon.entries.compactMap { entry in
            let score: Double
            switch direction {
            case .wordToMeaning:
                score = wordScore(query: query, entry: entry)
            case .meaningToWord:
                score = semanticScore(query: query, entry: entry)
            }
            return score > 0 ? SearchResult(entry: entry, score: score) : nil
        }
        .sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.entry.word < rhs.entry.word : lhs.score > rhs.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func wordScore(query: String, entry: LexicalEntry) -> Double {
        if normalize(entry.word) == query { return 100 }
        if entry.aliases.map(normalize).contains(query) { return 90 }
        if normalize(entry.word).contains(query) || query.contains(normalize(entry.word)) { return 50 }
        return dice(query, normalize(entry.word)) * 20
    }

    private func semanticScore(query: String, entry: LexicalEntry) -> Double {
        let fields = [entry.summary] + entry.cues + entry.aliases + [entry.word]
        var best = 0.0
        var cueHits = 0.0

        for field in fields {
            let normalizedField = normalize(field)
            if query.contains(normalizedField) || normalizedField.contains(query) {
                best = max(best, 20 + Double(min(query.count, normalizedField.count)))
            }
            best = max(best, dice(query, normalizedField) * 15)
            let fieldBigrams = bigrams(normalizedField)
            cueHits += Double(bigrams(query).intersection(fieldBigrams).count) * 0.8
        }
        return best + min(cueHits, 12)
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.widthInsensitive, .caseInsensitive], locale: .init(identifier: "ja_JP"))
            .filter { !$0.isWhitespace && !"。、，．！？・「」『』（）()".contains($0) }
    }

    private func bigrams(_ value: String) -> Set<String> {
        let chars = Array(value)
        guard chars.count > 1 else { return Set(chars.map(String.init)) }
        return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
    }

    private func dice(_ lhs: String, _ rhs: String) -> Double {
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else { return lhs == rhs ? 1 : 0 }
        return 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
    }
}

import Foundation

enum AIProviderKind: String, CaseIterable, Identifiable {
    case anthropic
    var id: Self { self }
    var label: String {
        switch self {
        case .anthropic: "Anthropic"
        }
    }
    var keychainAccount: String { "\(rawValue)-api-key" }
}

enum ConnectionState: Equatable {
    case unknown
    case checking
    case connected
    case failed(String)
}

/// AI Providerの設定、問い合わせ、短時間キャッシュを管理する
@MainActor
final class LanguageAssistant: ObservableObject {
    static let shared = LanguageAssistant()

    @Published private(set) var hasAPIKey = false
    @Published private(set) var connectionState: ConnectionState = .unknown
    @Published private(set) var lastSentTranscript: String?

    let providerKind = AIProviderKind.anthropic
    private var apiKey: String?
    private var cache = ResponseCache()
    private let makeProvider: (String) -> any LanguageAssistantProvider

    init(
        apiKey: String? = KeychainStore.read(account: AIProviderKind.anthropic.keychainAccount),
        makeProvider: @escaping (String) -> any LanguageAssistantProvider = { AnthropicLanguageProvider(apiKey: $0) }
    ) {
        self.apiKey = apiKey
        self.makeProvider = makeProvider
        hasAPIKey = !(apiKey ?? "").isEmpty
    }

    func respond(to request: LanguageRequest) async throws -> LanguageResponse {
        if let cached = cache.value(for: request) { return cached }
        guard let apiKey, !apiKey.isEmpty else { throw LanguageAssistantError.missingAPIKey }
        lastSentTranscript = LanguagePrompt.transcript(for: request)
        let response = try await makeProvider(apiKey).request(request)
        try Task.checkCancellation()
        cache.insert(response, for: request)
        return response
    }

    func saveAPIKey(_ value: String) async {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.save(key, account: providerKind.keychainAccount)
            apiKey = key
            hasAPIKey = true
            cache = ResponseCache()
            await verifyConnection()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func deleteAPIKey() {
        KeychainStore.delete(account: providerKind.keychainAccount)
        apiKey = nil
        hasAPIKey = false
        connectionState = .unknown
        cache = ResponseCache()
    }

    func verifyConnection() async {
        guard let apiKey, !apiKey.isEmpty else {
            connectionState = .failed(LanguageAssistantError.missingAPIKey.localizedDescription)
            return
        }
        connectionState = .checking
        do {
            try await makeProvider(apiKey).verify()
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }
}

/// 同じ問い合わせを短時間に繰り返さないためのメモリキャッシュ
struct ResponseCache {
    var lifetime: TimeInterval = 600
    var capacity = 100
    private var entries: [LanguageRequest: (response: LanguageResponse, date: Date)] = [:]

    func value(for request: LanguageRequest, now: Date = Date()) -> LanguageResponse? {
        guard let entry = entries[request], now.timeIntervalSince(entry.date) < lifetime else { return nil }
        return entry.response
    }

    mutating func insert(_ response: LanguageResponse, for request: LanguageRequest, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.date) < lifetime }
        if entries.count >= capacity, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries[oldest] = nil
        }
        entries[request] = (response, now)
    }
}

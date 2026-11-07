import Foundation

/// オンデバイスモデルへの問い合わせ、利用可否、短時間キャッシュを管理する
@MainActor
final class LanguageAssistant: ObservableObject {
    static let shared = LanguageAssistant()

    @Published private(set) var availability: ModelAvailability
    @Published private(set) var lastPrompt: String?

    private var cache = ResponseCache()
    private let provider: any LanguageAssistantProvider
    private let checkAvailability: () -> ModelAvailability

    init(
        provider: any LanguageAssistantProvider = AppleLanguageProvider(),
        checkAvailability: @escaping () -> ModelAvailability = { AppleLanguageProvider.availability }
    ) {
        self.provider = provider
        self.checkAvailability = checkAvailability
        availability = checkAvailability()
    }

    @discardableResult
    func refreshAvailability() -> ModelAvailability {
        availability = checkAvailability()
        return availability
    }

    func prewarm() {
        guard refreshAvailability().isAvailable else { return }
        AppleLanguageProvider.prewarm()
    }

    func respond(to request: LanguageRequest) async throws -> LanguageResponse {
        if let cached = cache.value(for: request) { return cached }
        guard refreshAvailability().isAvailable else { throw LanguageAssistantError.modelUnavailable(availability) }
        lastPrompt = LanguagePrompt.prompt(for: request)
        let response = try await provider.request(request)
        try Task.checkCancellation()
        cache.insert(response, for: request)
        return response
    }
}

/// 同じ入力の再生成を避け、応答を速くし計算量を減らすためのメモリキャッシュ
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

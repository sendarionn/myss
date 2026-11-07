import Foundation

@MainActor
final class SemanticSearchEngine {
    static let shared = SemanticSearchEngine()
    private let baseURL = URL(string: "http://127.0.0.1:52791")!
    private var backendProcess: Process?
    private var didAttemptStart = false

    func direction(for text: String) -> SearchDirection {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .meaningToWord }
        if normalized.count <= 8, !normalized.contains(where: "。！？、\n".contains) {
            return .wordToMeaning
        }
        return .meaningToWord
    }

    func status() async -> BackendStatus {
        do {
            try await ensureStarted()
            let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return BackendStatus(ready: false, model: nil, senseCount: nil, message: "検索データを準備できません")
            }
            return try JSONDecoder().decode(BackendStatus.self, from: data)
        } catch {
            return BackendStatus(ready: false, model: nil, senseCount: nil, message: error.localizedDescription)
        }
    }

    func search(query: String, direction: SearchDirection, limit: Int = 10) async throws -> SearchResponse {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SearchResponse(senses: [], phase: "local") }
        try await ensureStarted()
        var request = URLRequest(url: baseURL.appending(path: "search"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "direction": direction == .meaningToWord ? "meaningToWord" : "wordToMeaning",
            "limit": limit
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SemanticBackendError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            throw SemanticBackendError.server(body?["error"] ?? "検索に失敗しました")
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    func stop() {
        guard let backendProcess else { return }
        if backendProcess.isRunning { backendProcess.terminate() }
        self.backendProcess = nil
        didAttemptStart = false
    }

    private func ensureStarted() async throws {
        if await isHealthy() { return }
        guard !didAttemptStart else {
            throw SemanticBackendError.unavailable("検索データが未準備です　Scripts/setup-semantic-search.shを実行してください")
        }
        didAttemptStart = true
        let environment = ProcessInfo.processInfo.environment
        let projectRoot = environment["MYSS_PROJECT_ROOT"] ?? FileManager.default.currentDirectoryPath
        let pythonPath = environment["MYSS_BACKEND_PYTHON"] ?? "\(projectRoot)/.myss-runtime/bin/python3"
        let dataPath = environment["MYSS_DATA_PATH"] ?? "\(projectRoot)/.myss-data"
        let bundledBackend = Bundle.module.url(forResource: "Backend", withExtension: nil)?
            .appending(path: "semantic_backend.py").path
        let backendPath = bundledBackend ?? "\(projectRoot)/Sources/myss/Backend/semantic_backend.py"
        guard FileManager.default.isExecutableFile(atPath: pythonPath),
              FileManager.default.fileExists(atPath: "\(dataPath)/embeddings.npy") else {
            throw SemanticBackendError.unavailable("検索データが未準備です　Scripts/setup-semantic-search.shを実行してください")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [backendPath, "serve", "--data", dataPath, "--port", "52791"]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        backendProcess = process
        for _ in 0..<600 {
            try await Task.sleep(for: .milliseconds(100))
            if await isHealthy() { return }
        }
        throw SemanticBackendError.unavailable("検索バックエンドを起動できませんでした")
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 0.2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

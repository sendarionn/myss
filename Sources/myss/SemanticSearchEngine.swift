import Foundation
import Combine

@MainActor
final class SemanticSearchEngine: ObservableObject {
    static let shared = SemanticSearchEngine()
    @Published private(set) var lifecycleState: BackendLifecycleState = ApplicationPaths.isSearchDataReady ? .starting : .notConfigured
    private let baseURL = URL(string: "http://127.0.0.1:52791")!
    private var backendProcess: Process?
    private var startupTask: Task<Void, Error>?

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

    func prewarm() async {
        guard ApplicationPaths.isSearchDataReady else {
            lifecycleState = .notConfigured
            return
        }
        do { try await ensureStarted() }
        catch { lifecycleState = .error(error.localizedDescription) }
    }

    func stop() {
        guard let backendProcess else { return }
        if backendProcess.isRunning { backendProcess.terminate() }
        self.backendProcess = nil
        startupTask?.cancel()
        startupTask = nil
        lifecycleState = ApplicationPaths.isSearchDataReady ? .starting : .notConfigured
    }

    private func ensureStarted() async throws {
        if await isHealthy() {
            lifecycleState = .ready
            return
        }
        if let startupTask {
            try await startupTask.value
            return
        }
        guard ApplicationPaths.isSearchDataReady else {
            lifecycleState = .notConfigured
            throw SemanticBackendError.unavailable("検索データが未準備です　設定から検索データを準備してください")
        }
        lifecycleState = .starting
        let task = Task { try await startBackend() }
        startupTask = task
        do {
            try await task.value
            startupTask = nil
            lifecycleState = .ready
        } catch {
            startupTask = nil
            lifecycleState = .error(error.localizedDescription)
            throw error
        }
    }

    private func startBackend() async throws {
        let environment = ProcessInfo.processInfo.environment
        let pythonPath = environment["MYSS_BACKEND_PYTHON"] ?? ApplicationPaths.pythonExecutable.path
        let dataPath = environment["MYSS_DATA_PATH"] ?? ApplicationPaths.dataDirectory.path
        let bundledBackend = Bundle.module.url(forResource: "Backend", withExtension: nil)?
            .appending(path: "semantic_backend.py").path
        let backendPath = bundledBackend ?? ""
        guard FileManager.default.isExecutableFile(atPath: pythonPath),
              FileManager.default.fileExists(atPath: "\(dataPath)/embeddings.npy") else {
            throw SemanticBackendError.unavailable("検索データが未準備です　設定から検索データを準備してください")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [backendPath, "serve", "--data", dataPath, "--port", "52791"]
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment["HF_HOME"] = ApplicationPaths.modelDirectory.path
        processEnvironment["PYTHONUNBUFFERED"] = "1"
        process.environment = processEnvironment
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

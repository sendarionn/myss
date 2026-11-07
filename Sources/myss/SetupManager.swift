import Foundation

enum SetupStage: String, Sendable {
    case idle = "未準備"
    case runtime = "検索環境を準備中"
    case dependencies = "Embeddingモデルを準備中"
    case wordnet = "日本語WordNetを準備中"
    case index = "検索インデックスを作成中"
    case ready = "準備済み"
    case failed = "準備に失敗"
}

@MainActor
final class SetupManager: ObservableObject {
    static let shared = SetupManager()

    @Published private(set) var stage: SetupStage = ApplicationPaths.isSearchDataReady ? .ready : .idle
    @Published private(set) var progress = ApplicationPaths.isSearchDataReady ? 1.0 : 0.0
    @Published private(set) var errorMessage: String?
    private var setupTask: Task<Void, Never>?

    var isRunning: Bool {
        ![SetupStage.idle, .ready, .failed].contains(stage)
    }

    func prepare() {
        guard !isRunning else { return }
        setupTask = Task {
            do {
                try ApplicationPaths.createDirectories()
                stage = .runtime
                progress = 0.08
                try await run("/usr/bin/env", arguments: [
                    "python3", "-m", "venv", ApplicationPaths.runtimeDirectory.path
                ])

                stage = .dependencies
                progress = 0.2
                try await run(ApplicationPaths.pythonExecutable.path, arguments: [
                    "-m", "pip", "install", "--disable-pip-version-check", "--upgrade",
                    "sentence-transformers>=3.4,<6", "transformers>=4.48,<6", "numpy"
                ])

                stage = .wordnet
                progress = 0.45
                guard let backend = bundledBackendPath else {
                    throw SetupError.backendMissing
                }

                stage = .index
                progress = 0.55
                try await run(ApplicationPaths.pythonExecutable.path, arguments: [
                    backend, "setup",
                    "--data", ApplicationPaths.dataDirectory.path,
                    "--downloads", ApplicationPaths.downloadDirectory.path,
                    "--batch-size", "128"
                ])
                progress = 1
                stage = .ready
                errorMessage = nil
                await SemanticSearchEngine.shared.prewarm()
            } catch is CancellationError {
                stage = ApplicationPaths.isSearchDataReady ? .ready : .idle
            } catch {
                stage = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func rebuild() {
        SemanticSearchEngine.shared.stop()
        stage = .idle
        progress = 0
        prepare()
    }

    private var bundledBackendPath: String? {
        Bundle.module.url(forResource: "Backend", withExtension: nil)?
            .appending(path: "semantic_backend.py").path
    }

    private func run(_ executable: String, arguments: [String]) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: SetupError.commandFailed(process.terminationStatus))
                    }
                }
                do { try process.run() }
                catch { continuation.resume(throwing: error) }
            }
        } onCancel: {}
    }
}

enum SetupError: LocalizedError {
    case backendMissing
    case commandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .backendMissing: "検索バックエンドがアプリ内に見つかりません"
        case let .commandFailed(status): "検索データの準備に失敗しました　終了コード \(status)"
        }
    }
}

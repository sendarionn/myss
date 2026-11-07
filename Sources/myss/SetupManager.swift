import CryptoKit
import Foundation

enum SetupStage: String, Sendable {
    case idle = "未準備"
    case environment = "アプリ環境を確認中"
    case index = "検索indexを準備中"
    case runtime = "Python runtimeを準備中"
    case dependencies = "依存パッケージを確認中"
    case model = "Embeddingモデルを準備中"
    case engine = "検索エンジンを起動中"
    case ready = "準備済み"
    case failed = "準備に失敗"
}

enum SetupStep: String, CaseIterable, Identifiable {
    case environment = "アプリ環境"
    case index = "検索index"
    case model = "Embeddingモデル"
    case engine = "検索エンジン"
    var id: Self { self }
}

enum SetupStepState: Equatable {
    case pending
    case running
    case complete
    case failed
}

struct CommandResult: Sendable {
    let executable: String
    let arguments: [String]
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let stage: SetupStage

    var command: String { ([executable] + arguments).joined(separator: " ") }
}

struct IndexManifest: Codable {
    let indexVersion: String
    let archive: String
    let sha256: String
    let size: Int
}

struct IndexMetadata: Codable {
    let indexVersion: String
    let wordnetVersion: String
    let model: String
    let embeddingDimensions: Int
    let senseCount: Int
    let sha256: String
    let createdAt: String
}

@MainActor
final class SetupManager: ObservableObject {
    static let shared = SetupManager()

    @Published private(set) var stage: SetupStage = ApplicationPaths.isSearchDataReady ? .ready : .idle
    @Published private(set) var progress = ApplicationPaths.isSearchDataReady ? 1.0 : 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorDetails: String?
    @Published private(set) var stepStates: [SetupStep: SetupStepState] = [
        .environment: .pending, .index: .pending, .model: .pending, .engine: .pending
    ]
    private var setupTask: Task<Void, Never>?
    private var forceIndexInstall = false

    var isRunning: Bool {
        ![SetupStage.idle, .ready, .failed].contains(stage)
    }

    func prepare() {
        guard !isRunning else { return }
        errorMessage = nil
        errorDetails = nil
        setupTask = Task {
            do {
                try ApplicationPaths.createDirectories()
                try resetLog()

                setStep(.environment, state: .running, stage: .environment, progress: 0.05)
                let basePython = try await detectPython()
                setStep(.environment, state: .complete, stage: .environment, progress: 0.15)

                setStep(.index, state: .running, stage: .index, progress: 0.2)
                let installedIndexIsValid = try isInstalledIndexValid()
                if forceIndexInstall || !installedIndexIsValid {
                    try await installPrebuiltIndex()
                }
                forceIndexInstall = false
                setStep(.index, state: .complete, stage: .index, progress: 0.45)

                setStep(.model, state: .running, stage: .runtime, progress: 0.5)
                try await prepareRuntime(basePython: basePython)
                stage = .dependencies
                progress = 0.6
                try await prepareDependencies()
                stage = .model
                progress = 0.72
                try await prepareModel()
                setStep(.model, state: .complete, stage: .model, progress: 0.88)

                setStep(.engine, state: .running, stage: .engine, progress: 0.92)
                await SemanticSearchEngine.shared.prewarm()
                guard SemanticSearchEngine.shared.lifecycleState == .ready else {
                    throw SetupError.engineFailed(SemanticSearchEngine.shared.lifecycleState.label)
                }
                setStep(.engine, state: .complete, stage: .ready, progress: 1)
                errorMessage = nil
                errorDetails = nil
            } catch is CancellationError {
                stage = ApplicationPaths.isSearchDataReady ? .ready : .idle
            } catch {
                stage = .failed
                if let commandError = error as? SetupCommandError {
                    stepStates[step(for: commandError.result.stage)] = .failed
                    errorMessage = "\(commandError.result.stage.rawValue)に失敗しました"
                    errorDetails = commandError.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                    errorDetails = error.localizedDescription
                }
            }
        }
    }

    func retry() { prepare() }

    func repairIndex() {
        forceIndexInstall = true
        SemanticSearchEngine.shared.stop()
        stage = .idle
        progress = 0
        prepare()
    }

    private func setStep(_ step: SetupStep, state: SetupStepState, stage: SetupStage, progress: Double) {
        stepStates[step] = state
        self.stage = stage
        self.progress = progress
    }

    private func step(for stage: SetupStage) -> SetupStep {
        switch stage {
        case .environment: .environment
        case .index: .index
        case .runtime, .dependencies, .model: .model
        case .engine: .engine
        default: .environment
        }
    }

    private func detectPython() async throws -> String {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            if let result = try? await run(candidate, arguments: [
                "-c", "import sys,venv; assert sys.version_info >= (3,10); print(sys.executable)"
            ], stage: .environment), result.terminationStatus == 0 {
                return candidate
            }
        }
        throw SetupError.pythonUnavailable
    }

    private func prepareRuntime(basePython: String) async throws {
        if FileManager.default.isExecutableFile(atPath: ApplicationPaths.pythonExecutable.path) {
            let check = try? await run(
                ApplicationPaths.pythonExecutable.path,
                arguments: ["--version"],
                stage: .runtime
            )
            if check?.terminationStatus == 0 { return }
        }
        try? FileManager.default.removeItem(at: ApplicationPaths.runtimeDirectory)
        let result = try await run(basePython, arguments: [
            "-m", "venv", ApplicationPaths.runtimeDirectory.path
        ], stage: .runtime)
        try requireSuccess(result)
    }

    private func prepareDependencies() async throws {
        let check = try await run(ApplicationPaths.pythonExecutable.path, arguments: [
            "-c", "import numpy,torch,transformers,sentence_transformers"
        ], stage: .dependencies)
        if check.terminationStatus == 0 { return }
        let install = try await run(ApplicationPaths.pythonExecutable.path, arguments: [
            "-m", "pip", "install", "--disable-pip-version-check", "--upgrade",
            "sentence-transformers>=3.4,<6", "transformers>=4.48,<6", "numpy"
        ], stage: .dependencies)
        try requireSuccess(install)
    }

    private func prepareModel() async throws {
        guard let backend = bundledBackendPath else { throw SetupError.backendMissing }
        let result = try await run(ApplicationPaths.pythonExecutable.path, arguments: [
            backend, "prepare-model"
        ], stage: .model, environment: backendEnvironment)
        try requireSuccess(result)
        try FileManager.default.createDirectory(at: ApplicationPaths.modelDirectory, withIntermediateDirectories: true)
        try Data(result.stdout.utf8).write(to: ApplicationPaths.modelReadyFile, options: .atomic)
    }

    private func installPrebuiltIndex() async throws {
        let resources = Bundle.main.resourceURL?.appending(path: "PrebuiltIndex")
        let developmentResources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "dist/PrebuiltIndex")
        let root = [resources, developmentResources].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appending(path: "manifest.json").path)
        }
        guard let root else { throw SetupError.indexAssetMissing }
        let manifest = try JSONDecoder().decode(
            IndexManifest.self,
            from: Data(contentsOf: root.appending(path: "manifest.json"))
        )
        let sourceArchive = root.appending(path: manifest.archive)
        guard try sha256(of: sourceArchive) == manifest.sha256 else { throw SetupError.archiveChecksumMismatch }

        let work = ApplicationPaths.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let archive = work.appending(path: manifest.archive)
        let extracted = work.appending(path: "Extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceArchive, to: archive)
        let extraction = try await run("/usr/bin/tar", arguments: [
            "-xzf", archive.path, "-C", extracted.path
        ], stage: .index)
        try requireSuccess(extraction)
        try validateIndex(at: extracted)

        let backup = ApplicationPaths.supportDirectory.appending(path: "Data.backup")
        try? FileManager.default.removeItem(at: backup)
        if FileManager.default.fileExists(atPath: ApplicationPaths.dataDirectory.path) {
            try FileManager.default.moveItem(at: ApplicationPaths.dataDirectory, to: backup)
        }
        do {
            try FileManager.default.moveItem(at: extracted, to: ApplicationPaths.dataDirectory)
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.removeItem(at: work)
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: ApplicationPaths.dataDirectory)
            }
            throw error
        }
    }

    private func isInstalledIndexValid() throws -> Bool {
        guard FileManager.default.fileExists(atPath: ApplicationPaths.embeddingsFile.path),
              FileManager.default.fileExists(atPath: ApplicationPaths.sensesFile.path),
              FileManager.default.fileExists(atPath: ApplicationPaths.metadataFile.path) else { return false }
        do {
            try validateIndex(at: ApplicationPaths.dataDirectory)
            return true
        } catch {
            return false
        }
    }

    private func validateIndex(at directory: URL) throws {
        let senses = directory.appending(path: "senses.json")
        let embeddings = directory.appending(path: "embeddings.npy")
        let metadataURL = directory.appending(path: "metadata.json")
        guard FileManager.default.fileExists(atPath: senses.path),
              FileManager.default.fileExists(atPath: embeddings.path),
              FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw SetupError.incompleteIndex
        }
        let metadata = try JSONDecoder().decode(IndexMetadata.self, from: Data(contentsOf: metadataURL))
        var digest = SHA256()
        try update(&digest, from: senses)
        try update(&digest, from: embeddings)
        guard digest.finalize().hex == metadata.sha256,
              metadata.senseCount == 57_885,
              metadata.embeddingDimensions == 384 else {
            throw SetupError.indexChecksumMismatch
        }
    }

    private var bundledBackendPath: String? {
        Bundle.module.url(forResource: "Backend", withExtension: nil)?
            .appending(path: "semantic_backend.py").path
    }

    private var backendEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = ApplicationPaths.modelDirectory.path
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    func run(
        _ executable: String,
        arguments: [String],
        stage: SetupStage,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        try appendLog("\n[\(ISO8601DateFormatter().string(from: Date()))] [\(stage.rawValue)] \(([executable] + arguments).joined(separator: " "))\n")
        let collector = ProcessOutputCollector()
        let result: CommandResult = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in collector.appendStdout(handle.availableData) }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in collector.appendStderr(handle.availableData) }
            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                collector.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                collector.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                let output = collector.snapshot()
                continuation.resume(returning: CommandResult(
                    executable: executable,
                    arguments: arguments,
                    stdout: output.stdout,
                    stderr: output.stderr,
                    terminationStatus: process.terminationStatus,
                    stage: stage
                ))
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        try appendLog("stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)\n終了コード: \(result.terminationStatus)\n")
        return result
    }

    private func requireSuccess(_ result: CommandResult) throws {
        guard result.terminationStatus == 0 else { throw SetupCommandError(result: result) }
    }

    private func resetLog() throws {
        try Data().write(to: ApplicationPaths.setupLog, options: .atomic)
    }

    private func appendLog(_ value: String) throws {
        let data = Data(value.utf8)
        if let handle = try? FileHandle(forWritingTo: ApplicationPaths.setupLog) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: ApplicationPaths.setupLog, options: .atomic)
        }
    }

    private func sha256(of url: URL) throws -> String {
        var digest = SHA256()
        try update(&digest, from: url)
        return digest.finalize().hex
    }

    private func update(_ digest: inout SHA256, from url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) { lock.withLock { stdoutData.append(data) } }
    func appendStderr(_ data: Data) { lock.withLock { stderrData.append(data) } }
    func snapshot() -> (stdout: String, stderr: String) {
        lock.withLock {
            (String(decoding: stdoutData, as: UTF8.self), String(decoding: stderrData, as: UTF8.self))
        }
    }
}

struct SetupCommandError: LocalizedError {
    let result: CommandResult
    var errorDescription: String? {
        let tail = String(result.stderr.suffix(4_000))
        return """
        \(result.stage.rawValue)に失敗しました

        \(result.command)
        終了コード: \(result.terminationStatus)

        \(tail.isEmpty ? String(result.stdout.suffix(4_000)) : tail)
        """
    }
}

enum SetupError: LocalizedError {
    case pythonUnavailable
    case backendMissing
    case indexAssetMissing
    case archiveChecksumMismatch
    case incompleteIndex
    case indexChecksumMismatch
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonUnavailable: "利用可能なPython 3.10以降が見つかりません"
        case .backendMissing: "検索バックエンドがアプリ内に見つかりません"
        case .indexAssetMissing: "事前生成済み検索indexがアプリ内に見つかりません"
        case .archiveChecksumMismatch: "検索indexの配布ファイルが破損しています"
        case .incompleteIndex: "検索indexに必要なファイルが不足しています"
        case .indexChecksumMismatch: "検索indexの整合性を確認できません"
        case let .engineFailed(message): "検索エンジンを起動できません　\(message)"
        }
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

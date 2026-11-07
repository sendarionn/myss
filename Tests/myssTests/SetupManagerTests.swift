import XCTest
@testable import myss

final class SetupManagerTests: XCTestCase {
    @MainActor
    func testProcessOutputIsDrainedAndFailureDetailsAreRetained() async throws {
        try ApplicationPaths.createDirectories()
        let previousLog = try? Data(contentsOf: ApplicationPaths.setupLog)
        defer {
            if let previousLog { try? previousLog.write(to: ApplicationPaths.setupLog, options: .atomic) }
            else { try? FileManager.default.removeItem(at: ApplicationPaths.setupLog) }
        }
        let size = 256 * 1024
        let result = try await SetupManager.shared.run(
            "/usr/bin/python3",
            arguments: [
                "-c",
                "import sys; sys.stdout.write('o' * \(size)); sys.stderr.write('e' * \(size)); sys.exit(7)"
            ],
            stage: .dependencies
        )

        XCTAssertEqual(result.terminationStatus, 7)
        XCTAssertEqual(result.stdout.utf8.count, size)
        XCTAssertEqual(result.stderr.utf8.count, size)
        XCTAssertEqual(result.executable, "/usr/bin/python3")
        XCTAssertEqual(result.stage, .dependencies)
    }

    @MainActor
    func testInstalledSetupPipelineWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MYSS_RUN_SETUP_INTEGRATION"] == "1" else {
            throw XCTSkip("実機セットアップ確認時だけ実行")
        }

        let manager = SetupManager.shared
        defer { SemanticSearchEngine.shared.stop() }
        manager.repairIndex()
        let deadline = Date().addingTimeInterval(600)
        while manager.isRunning || manager.stage == .idle {
            if Date() >= deadline { XCTFail("セットアップがタイムアウト"); return }
            try await Task.sleep(for: .milliseconds(200))
        }

        XCTAssertEqual(manager.stage, .ready, manager.errorDetails ?? manager.errorMessage ?? "")
        XCTAssertTrue(ApplicationPaths.isSearchDataReady)
        XCTAssertEqual(SemanticSearchEngine.shared.lifecycleState, .ready)
    }
}

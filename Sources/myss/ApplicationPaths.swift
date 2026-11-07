import Foundation

enum ApplicationPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "myss", directoryHint: .isDirectory)
    }()

    static let runtimeDirectory = supportDirectory.appending(path: "Runtime", directoryHint: .isDirectory)
    static let dataDirectory = supportDirectory.appending(path: "Data", directoryHint: .isDirectory)
    static let downloadDirectory = supportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    static let temporaryDirectory = supportDirectory.appending(path: "Temporary", directoryHint: .isDirectory)
    static let modelDirectory = supportDirectory.appending(path: "Model", directoryHint: .isDirectory)
    static let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/myss", directoryHint: .isDirectory)
    static let setupLog = logDirectory.appending(path: "setup.log")
    static let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "myss", directoryHint: .isDirectory)
    }()

    static var pythonExecutable: URL { runtimeDirectory.appending(path: "bin/python3") }
    static var embeddingsFile: URL { dataDirectory.appending(path: "embeddings.npy") }
    static var sensesFile: URL { dataDirectory.appending(path: "senses.json") }
    static var metadataFile: URL { dataDirectory.appending(path: "metadata.json") }
    static var modelReadyFile: URL { modelDirectory.appending(path: "ready.json") }

    static var isSearchDataReady: Bool {
        FileManager.default.isExecutableFile(atPath: pythonExecutable.path)
            && FileManager.default.fileExists(atPath: embeddingsFile.path)
            && FileManager.default.fileExists(atPath: sensesFile.path)
            && FileManager.default.fileExists(atPath: metadataFile.path)
    }

    static func createDirectories() throws {
        for directory in [supportDirectory, dataDirectory, downloadDirectory, temporaryDirectory, modelDirectory, cacheDirectory, logDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

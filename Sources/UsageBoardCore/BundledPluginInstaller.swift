@preconcurrency import Foundation

public struct BundledPluginInstaller: Sendable {
    public var sourceDirectoryURL: URL
    public var destinationDirectoryURL: URL

    public init(sourceDirectoryURL: URL, destinationDirectoryURL: URL = ConfigStore.pluginsDirectoryURL()) {
        self.sourceDirectoryURL = sourceDirectoryURL
        self.destinationDirectoryURL = destinationDirectoryURL
    }

    @discardableResult
    public func installIfNeeded() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceDirectoryURL.path) else {
            return []
        }

        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let sourceFiles = try fileManager.contentsOfDirectory(
            at: sourceDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "py" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var installed: [URL] = []
        for sourceURL in sourceFiles {
            let destinationURL = destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
            installed.append(destinationURL)
        }
        return installed
    }
}

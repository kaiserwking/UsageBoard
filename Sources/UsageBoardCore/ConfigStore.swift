@preconcurrency import Foundation

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = ConfigStore.defaultConfigURL()) {
        self.fileURL = fileURL
    }

    public static func defaultConfigURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("config.json")
    }

    public static func defaultConfigurationDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("UsageBoard", isDirectory: true)
    }

    public static func statesDirectoryURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("states", isDirectory: true)
    }

    public static func pluginsDirectoryURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("plugins", isDirectory: true)
    }

    public func pluginsDirectoryURL() -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("plugins", isDirectory: true)
    }

    public func loadOrCreate() throws -> AppConfiguration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try load()
        }
        let configuration = AppConfiguration()
        try save(configuration)
        return configuration
    }

    public func load() throws -> AppConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try UsageBoardJSON.encoder().encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
    }
}

@preconcurrency import Foundation

public enum PluginDisplayNames {
    public static func make(for plugins: [PluginConfiguration]) -> [UUID: String] {
        var counts: [String: Int] = [:]
        var names: [UUID: String] = [:]

        for plugin in plugins {
            let baseName = plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : plugin.name
            let nextCount = (counts[baseName] ?? 0) + 1
            counts[baseName] = nextCount
            names[plugin.id] = nextCount == 1 ? baseName : "\(baseName) \(nextCount)"
        }

        return names
    }
}

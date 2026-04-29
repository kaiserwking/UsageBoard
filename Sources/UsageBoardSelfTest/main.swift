@preconcurrency import Foundation
import UsageBoardCore

enum SelfTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfTestError.failed(message)
    }
}

func runSelfTests() throws {
    let configurationData = #"{"plugins":[{"name":"A","executablePath":"/bin/echo"}]}"#.data(using: .utf8)!
    let configuration = try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: configurationData)
    try expect(configuration.schemaVersion == 1, "configuration schema default")
    try expect(configuration.mainDisplayMode == .grouped, "main display default")
    try expect(configuration.overviewDisplayMode == .tabs, "overview display default")
    try expect(configuration.plugins.first?.refreshIntervalSeconds == 300, "refresh interval default")

    let pluginData = """
    {
      "schemaVersion": 1,
      "updatedAt": "2026-04-29T00:00:00Z",
      "items": [
        {
          "id": "requests",
          "name": "Requests",
          "used": 1200,
          "limit": 1500,
          "displayStyle": "percent",
          "resetAt": "2026-04-29T00:05:00Z",
          "status": "normal"
        }
      ]
    }
    """.data(using: .utf8)!
    let output = try UsageBoardJSON.decoder().decode(PluginOutput.self, from: pluginData)
    let item = output.items[0]
    try expect(item.progress == 0.8, "progress calculation")
    try expect(item.displayValue() == "80%", "percent display")
    let now = ISO8601DateFormatter().date(from: "2026-04-29T00:00:00Z")!
    try expect(!item.resetText(now: now).contains("重置"), "reset text")

    let metadataScript = """
    #!/usr/bin/env python3
    # UsageBoardPlugin:
    # {"schemaVersion":1,"name":"GLM","parameters":[{"name":"API_KEY","type":"string","required":true},{"name":"PROVIDER","type":"choice","defaultValue":"GLM","options":[{"label":"GLM","value":"GLM"},{"label":"ZAI","value":"ZAI"}]}]}
    # /UsageBoardPlugin
    """
    let metadata = PluginMetadataParser.parse(text: metadataScript)
    try expect(metadata?.name == "GLM", "plugin metadata name")
    try expect(metadata?.parameters.first?.type == .string, "plugin metadata parameter type")
    try expect(metadata?.parameters.last?.options.count == 2, "plugin metadata options")

    let overLimit = UsageItem(id: "a", name: "A", used: 2, limit: 1, displayStyle: .percent)
    let noLimit = UsageItem(id: "b", name: "B", used: 2, limit: 0, displayStyle: .percent)
    let ratio = UsageItem(id: "c", name: "C", used: 2, limit: 1500, displayStyle: .ratio)
    try expect(overLimit.progress == 1, "progress clamps high")
    try expect(noLimit.progress == 0, "progress handles zero limit")
    try expect(ratio.displayValue() == "2/1500", "ratio display")
    try expect(ratio.resetText() == "--", "missing reset text")

    let first = PluginConfiguration(name: "OpenAI", executablePath: "/bin/echo")
    let second = PluginConfiguration(name: "OpenAI", executablePath: "/bin/echo")
    let names = PluginDisplayNames.make(for: [first, second])
    try expect(names[first.id] == "OpenAI", "first duplicate name")
    try expect(names[second.id] == "OpenAI 2", "second duplicate name")

    let executor = PluginExecutor(timeoutSeconds: 2)
    let parameterConfiguration = PluginConfiguration(
        name: "GLM",
        executablePath: "/tmp/glm.py",
        parameterValues: ["API_KEY": "secret", "PROVIDER": "ZAI", "EMPTY": ""]
    )
    try expect(
        executor.pluginParameterArguments(configuration: parameterConfiguration) == ["--usageboard-param", "API_KEY=secret", "--usageboard-param", "PROVIDER=ZAI"],
        "plugin parameter arguments"
    )

    try expect(UpdateChecker.isVersion("1.2.0", newerThan: "1.1.9"), "newer minor version")
    try expect(!UpdateChecker.isVersion("1.2.0", newerThan: "1.2.0"), "same version")

    let badPlugin = PluginConfiguration(name: "Bad", executablePath: "/bin/echo", arguments: ["not-json"])
    let snapshot = executor.run(configuration: badPlugin, displayName: "Bad")
    guard case .failed(let message) = snapshot.state else {
        throw SelfTestError.failed("invalid JSON should fail")
    }
    try expect(message.contains("JSON 解析失败"), "invalid JSON message")
}

do {
    try runSelfTests()
    print("UsageBoard self-test passed")
} catch {
    fputs("UsageBoard self-test failed: \(error)\n", stderr)
    exit(1)
}

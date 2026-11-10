import Foundation

public struct AdapterStatus: Codable, Identifiable, Sendable {
    public var id: String { toolID }
    public let toolID: String
    public let adapterVersion: Int
    public let version: String?
    public let effectiveCachePath: String?
    public let state: String
    public let explanation: String
    public let canReleaseSource: Bool
}

/// Native configuration discovery is kept separate from mutation and qualification.
public enum CacheAdapters {
    public static let version = 1
    public static let qualifiedVersions: [String:String] = {
        guard let url = L10n.resourceBundle?.url(forResource:"cache-qualification",withExtension:"json"), let data = try? Data(contentsOf:url) else { return [:] }
        return (try? JSONDecoder().decode([String:String].self,from:data)) ?? [:]
    }()
    public static func inspect(_ tool: CacheDescriptor, home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> AdapterStatus {
        func status(_ state: String, _ reason: String, version: String? = nil, path: String? = nil) -> AdapterStatus {
            AdapterStatus(toolID: tool.id, adapterVersion: self.version, version: version, effectiveCachePath: path, state: state, explanation: reason, canReleaseSource: state == "native-available" && tool.canReleaseLocal && version != nil && qualifiedVersions[tool.id] == version)
        }
        let name = ["cocoapods":"pod", "pip":"python3", "homebrew":"brew"][tool.id] ?? tool.id
        let executable = tool.id == "gradle" ? gradle(home: home) : ToolLocator.locate(name, home: home)
        guard let executable else { return status("missing-tool", "Ferramenta não localizada; nenhum cache será alterado.") }
        var env = ToolLocator.environment(adding: [:]); env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        let arguments = tool.id == "gradle" ? ["--version", "--no-daemon"] : tool.id == "pip" ? ["-m", "pip", "--version"] : ["--version"]
        guard let result = try? CommandRunner.run(executable, arguments, environment: env, timeout: 25), result.status == 0, !result.truncated else { return status("unavailable", "Não foi possível identificar a ferramenta. Preserve a configuração atual.") }
        let regex = try? NSRegularExpression(pattern: #"\b\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.]+)?"#)
        let range = NSRange(result.output.startIndex..., in: result.output)
        let match = regex?.firstMatch(in: result.output, range: range).flatMap { Range($0.range, in: result.output) }.map { String(result.output[$0]) }
        let custom = CacheRouter.hasCustomPreference(toolID: tool.id, directory: directory, home: home) || ProcessInfo.processInfo.environment[tool.environmentKey] != nil || (tool.id == "npm" && ProcessInfo.processInfo.environment["NPM_CONFIG_CACHE"] != nil)
        var query: [String] = []
        switch tool.id {
        case "npm": query = ["config", "get", "cache"]
        case "pip": query = ["-m", "pip", "cache", "dir"]
        case "uv": query = ["cache", "dir"]
        case "homebrew": query = ["--cache"]
        default: break
        }
        var path: String?
        if !query.isEmpty, let value = try? CommandRunner.run(executable, query, environment: env, timeout: 25), value.status == 0, !value.truncated {
            let candidate = value.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("/"), !candidate.contains("\n") { path = candidate }
        }
        if custom { return status("custom-configuration", "Configuração personalizada preservada. O cache padrão não comprova o destino desta execução.", version: match, path: path) }
        let reason = tool.canReleaseLocal ? "Ferramenta disponível. Revise origem e destino; a qualificação em projetos reais depende da versão testada." : "Novos downloads podem usar SSD; a origem local é preservada por possíveis links de instalações existentes."
        return status("native-available", reason, version: match, path: path)
    }
    public static func gradle(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let distributions = home.appendingPathComponent(".gradle/wrapper/dists")
        if let e = FileManager.default.enumerator(at: distributions, includingPropertiesForKeys: nil) {
            for case let url as URL in e where url.lastPathComponent == "gradle" && url.deletingLastPathComponent().lastPathComponent == "bin" {
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }
}

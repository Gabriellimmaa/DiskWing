import Foundation
import Darwin

public struct AdapterStatus: Codable, Identifiable, Sendable {
    public var id: String { toolID }
    public let toolID: String
    public let adapterVersion: Int
    public let version: String?
    public let effectiveCachePath: String?
    public let state: String
    public let explanation: String
    public let canReleaseSource: Bool
    public init(toolID: String, adapterVersion: Int, version: String?, effectiveCachePath: String?, state: String, explanation: String, canReleaseSource: Bool) {
        self.toolID = toolID; self.adapterVersion = adapterVersion; self.version = version
        self.effectiveCachePath = effectiveCachePath; self.state = state; self.explanation = explanation; self.canReleaseSource = canReleaseSource
    }
}

/// Native configuration discovery is kept separate from mutation and qualification.
public enum CacheAdapters {
    public static let version = 1
    public static let qualifiedVersions: [String:String] = {
        guard let url = L10n.resourceBundle?.url(forResource:"cache-qualification",withExtension:"json"), let data = try? Data(contentsOf:url) else { return [:] }
        return (try? JSONDecoder().decode([String:String].self,from:data)) ?? [:]
    }()
    /// Reading the installed package avoids `yarn cache dir`, which creates cache folders.
    /// Unknown shims (including Corepack) are deliberately not executed for discovery.
    static func yarnClassicVersion(home: URL) -> String? {
        guard let executable = ToolLocator.locate("yarn", home: home) else { return nil }
        let installation = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        for file in [installation.appendingPathComponent("package.json"), installation.appendingPathComponent("libexec/package.json")] {
            var metadata = stat()
            guard lstat(file.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_flags & UInt32(SF_DATALESS) == 0, metadata.st_size <= 1_048_576,
                  let data = try? Data(contentsOf: file), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any],
                  object["name"] as? String == "yarn", let version = object["version"] as? String,
                  version.hasPrefix("1.22.") else { continue }
            return version
        }
        return nil
    }
    public static func inspect(_ tool: CacheDescriptor, home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> AdapterStatus {
        func status(_ state: String, _ reason: String, version: String? = nil, path: String? = nil) -> AdapterStatus {
            AdapterStatus(toolID: tool.id, adapterVersion: self.version, version: version, effectiveCachePath: path, state: state, explanation: reason, canReleaseSource: state == "native-available" && tool.canReleaseLocal && version != nil && qualifiedVersions[tool.id] == version)
        }
        let name = ["cocoapods":"pod", "pip":"python3", "homebrew":"brew"][tool.id] ?? tool.id
        let executable = tool.id == "gradle" ? gradle(home: home) : ToolLocator.locate(name, home: home)
        guard let executable else { return status("missing-tool", "Ferramenta não localizada; nenhum cache será alterado.") }
        if tool.id == "yarn" {
            guard let version = yarnClassicVersion(home: home) else { return status("unsupported-version", "Somente uma instalação identificada do Yarn Classic 1.22 é compatível. Outras versões e executores indiretos são preservados.") }
            let custom = CacheRouter.hasCustomPreference(toolID: tool.id, directory: directory, home: home)
            return custom ? status("custom-configuration", "Configuração personalizada ou Plug’n’Play preservado. O cache local não será alterado.", version: version) : assess(tool, version: version, effectiveRoot: nil, custom: false, queried: false)
        }
        var env = ToolLocator.environment(adding: ["HOME":home.path]); env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        if tool.id == "go" { env["GOTOOLCHAIN"] = "local" }
        let arguments = tool.id == "gradle" ? ["--version", "--no-daemon"] : tool.id == "pip" ? ["-m", "pip", "--version"] : tool.id == "go" ? ["version"] : ["--version"]
        guard let result = try? CommandRunner.run(executable, arguments, environment: env, timeout: 25, directory: directory), result.status == 0, !result.truncated else { return status("unavailable", "Não foi possível identificar a ferramenta. Preserve a configuração atual.") }
        let regex = try? NSRegularExpression(pattern: tool.id == "go" ? #"(?<=go)\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.]+)?"# : #"\b\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.]+)?"#)
        let range = NSRange(result.output.startIndex..., in: result.output)
        let match = regex?.firstMatch(in: result.output, range: range).flatMap { Range($0.range, in: result.output) }.map { String(result.output[$0]) }
        let custom = CacheRouter.hasCustomPreference(toolID: tool.id, directory: directory, home: home) || ProcessInfo.processInfo.environment[tool.environmentKey] != nil || (tool.id == "npm" && ProcessInfo.processInfo.environment["NPM_CONFIG_CACHE"] != nil)
        var query: [String] = []
        switch tool.id {
        case "npm": query = ["config", "get", "cache"]
        case "pip": query = ["-m", "pip", "cache", "dir"]
        case "uv": query = ["cache", "dir"]
        case "homebrew": query = ["--cache"]
        case "go": query = ["env", "GOCACHE"]
        case "ccache": query = ["--get-config", "cache_dir"]
        default: break
        }
        var path: String?
        if !query.isEmpty, let value = try? CommandRunner.run(executable, query, environment: env, timeout: 25, directory: directory), value.status == 0, !value.truncated {
            let candidate = value.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("/"), !candidate.contains("\n") { path = candidate }
        }
        if custom { return status("custom-configuration", "Configuração personalizada preservada. O cache padrão não comprova o destino desta execução.", version: match, path: path) }
        return assess(tool, version: match, effectiveRoot: path, custom: false, queried: !query.isEmpty)
    }
    /// Pure policy seam; an exact tool version alone never proves the source path.
    static func assess(_ tool: CacheDescriptor, version: String?, effectiveRoot: String?, custom: Bool, queried: Bool) -> AdapterStatus {
        let expected = tool.destinationChild.isEmpty ? tool.source : tool.source.deletingLastPathComponent()
        let matches = effectiveRoot.map { Paths.physicalURL(URL(fileURLWithPath:$0)).path == Paths.physicalURL(expected).path } ?? false
        let state = custom || effectiveRoot != nil && !matches ? "custom-configuration" : queried && !matches ? "configuration-unverified" : "native-available"
        let verified = queried && state == "native-available" && matches
        let reason = state == "custom-configuration" ? "O destino efetivo é personalizado. A configuração e a origem foram preservadas." : state == "configuration-unverified" ? "Não foi possível confirmar o destino efetivo. A origem foi preservada." : tool.canReleaseLocal ? "Ferramenta disponível. Revise origem e destino; a qualificação em projetos reais depende da versão testada." : "Novas execuções podem usar SSD; a origem local é preservada por possíveis referências ou configurações de instalações existentes."
        return AdapterStatus(toolID:tool.id, adapterVersion:self.version, version:version, effectiveCachePath:effectiveRoot, state:state, explanation:reason, canReleaseSource:verified && tool.canReleaseLocal && version != nil && qualifiedVersions[tool.id] == version)
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

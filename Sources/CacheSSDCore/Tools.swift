import Foundation
import Darwin

public struct CacheDescriptor: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let explanation: String
    public let source: URL
    public let environmentKey: String
    public let destinationChild: String
    public init(id: String, name: String, explanation: String, source: URL, environmentKey: String, destinationChild: String = "") {
        self.id = id; self.name = name; self.explanation = explanation; self.source = source
        self.environmentKey = environmentKey; self.destinationChild = destinationChild
    }
    public func payload(at base: URL) -> URL { destinationChild.isEmpty ? base : base.appendingPathComponent(destinationChild) }
    public var canReleaseLocal: Bool {
        // PnP projects can execute packages directly from Yarn's cache, including Classic.
        if ["bun", "uv", "yarn"].contains(id) { return false }
        // ccache can store persistent user configuration alongside cached results.
        if id == "ccache", FileManager.default.fileExists(atPath: source.appendingPathComponent("ccache.conf").path) { return false }
        return true
    }
}

public enum CacheCatalog {
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CacheDescriptor] {
        [
            CacheDescriptor(id: "npm", name: "npm", explanation: "Pacotes baixados. Os executáveis locais do npx ficam preservados.", source: home.appendingPathComponent(".npm/_cacache"), environmentKey: "npm_config_cache", destinationChild: "_cacache"),
            CacheDescriptor(id: "bun", name: "Bun", explanation: "Novos downloads podem usar o SSD. A origem fica no Mac para preservar instalações existentes.", source: home.appendingPathComponent(".bun/install/cache"), environmentKey: "BUN_INSTALL_CACHE_DIR"),
            CacheDescriptor(id: "cocoapods", name: "CocoaPods", explanation: "Downloads de Pods. Repositórios, projetos e credenciais ficam no Mac.", source: home.appendingPathComponent("Library/Caches/CocoaPods"), environmentKey: "CP_CACHE_DIR"),
            CacheDescriptor(id: "pip", name: "pip", explanation: "Downloads e pacotes Python compilados; não inclui ambientes instalados.", source: home.appendingPathComponent("Library/Caches/pip"), environmentKey: "PIP_CACHE_DIR"),
            CacheDescriptor(id: "homebrew", name: "Homebrew", explanation: "Downloads. Os aplicativos e ferramentas instalados ficam no Mac.", source: home.appendingPathComponent("Library/Caches/Homebrew"), environmentKey: "HOMEBREW_CACHE"),
            CacheDescriptor(id: "gradle", name: "Gradle", explanation: "Caches de compilação. JDKs, distribuições e configurações continuam locais.", source: home.appendingPathComponent(".gradle/caches"), environmentKey: "GRADLE_USER_HOME", destinationChild: "caches"),
            CacheDescriptor(id: "uv", name: "uv", explanation: "Novos downloads podem usar o SSD. A origem fica no Mac para preservar ambientes existentes.", source: home.appendingPathComponent(".cache/uv"), environmentKey: "UV_CACHE_DIR"),
            CacheDescriptor(id: "yarn", name: "Yarn Classic", explanation: "Cache de pacotes do Yarn 1. A origem fica no Mac para preservar projetos Plug’n’Play existentes.", source: home.appendingPathComponent("Library/Caches/Yarn/v6"), environmentKey: "YARN_CACHE_FOLDER", destinationChild: "v6"),
            CacheDescriptor(id: "go", name: "Go", explanation: "Resultados de compilação. Módulos baixados, ferramentas instaladas e projetos ficam no Mac.", source: home.appendingPathComponent("Library/Caches/go-build"), environmentKey: "GOCACHE"),
            CacheDescriptor(id: "ccache", name: "ccache", explanation: "Resultados de compilação C/C++. Compiladores, projetos e configurações são preservados.", source: home.appendingPathComponent(FileManager.default.fileExists(atPath: home.appendingPathComponent(".ccache").path) ? ".ccache" : "Library/Caches/ccache"), environmentKey: "CCACHE_DIR")
        ]
    }
    public static func find(_ id: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheDescriptor? { all(home: home).first { $0.id == id } }
}

public struct CommandResult {
    public let status: Int32
    public let output: String
    public let truncated: Bool
}

public enum CommandRunner {
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 45, directory: URL? = nil, maxOutputBytes: Int = 262_144) throws -> CommandResult {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.currentDirectoryURL = directory
        process.standardOutput = pipe; process.standardError = pipe
        let capture = OutputCapture(limit: maxOutputBytes)
        pipe.fileHandleForReading.readabilityHandler = { handle in capture.append(handle.availableData) }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.03) }
        if process.isRunning {
            process.terminate(); Thread.sleep(forTimeInterval: 0.15)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            throw CacheSSDError.message(L10n.text("A ferramenta excedeu o tempo de verificação; nenhuma origem foi removida."))
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        capture.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return CommandResult(status: process.terminationStatus, output: capture.string, truncated: capture.truncated)
    }
    private final class OutputCapture: @unchecked Sendable {
        let lock = NSLock(); var data = Data(); let limit: Int; private var overflow = false
        init(limit: Int) { self.limit = limit }
        func append(_ bytes: Data) { lock.lock(); defer { lock.unlock() }; if data.count + bytes.count > limit { overflow = true }; if data.count < limit { data.append(bytes.prefix(limit - data.count)) } }
        var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
        var truncated: Bool { lock.lock(); defer { lock.unlock() }; return overflow }
    }
}

public enum ToolLocator {
    public static func locate(_ name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let systemDirectories = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { !systemDirectories.contains($0) }
        var runtimeDirectories: [String] = []
        for root in [home.appendingPathComponent(".nvm/versions/node"), home.appendingPathComponent(".rubies")] {
            let versions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            let bins = versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.map { $0.appendingPathComponent("bin").path }
            if (["pod", "ruby"].contains(name) && root.lastPathComponent == ".rubies") || (["node", "npm", "npx"].contains(name) && root.lastPathComponent == "node") { directories += bins }
            else { runtimeDirectories += bins }
        }
        directories += ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".bun/bin").path] + runtimeDirectories
        directories += systemDirectories
        for dir in directories {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
    public static func environment(adding values: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for name in ["node", "ruby", "bun"] { if let path = locate(name) { dirs.insert(path.deletingLastPathComponent().path, at: 0) } }
        env["PATH"] = dirs.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        for (key, value) in values { env[key] = value }
        return env
    }
}

public struct BusyProcess: Identifiable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
}

/// Injectable for controlled fixtures; production defaults keep the real
/// process/open-file inspection at every operation boundary.
public typealias BusyCheck = ([URL], String?) throws -> [BusyProcess]

public enum BusyInspector {
    public static func inspect(paths: [URL], tool: String? = nil) throws -> [BusyProcess] {
        let result = try CommandRunner.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-n", "-P", "-F", "pcn"], timeout: 30, maxOutputBytes: 33_554_432)
        guard !result.truncated else { throw CacheSSDError.message(L10n.text("A lista de arquivos em uso está incompleta. A operação foi adiada.")) }
        guard result.status == 0 || result.status == 1 else { throw CacheSSDError.message(L10n.text("Não foi possível verificar arquivos abertos. A operação foi adiada.")) }
        var pid = 0, name = "Processo", found: [Int: String] = [:]
        for line in result.output.split(separator: "\n") {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            if prefix == "p" { pid = Int(value) ?? 0 }
            if prefix == "c" { name = value }
            if prefix == "n", value.hasPrefix("/"), paths.contains(where: { Paths.contains(URL(fileURLWithPath: value), in: $0) }) { found[pid] = name }
        }
        // A command may close a cache file between two writes. Also check the known clients.
        let ps = try CommandRunner.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid=,command="], timeout: 10, maxOutputBytes: 16_777_216)
        guard ps.status == 0, !ps.truncated else { throw CacheSSDError.message(L10n.text("Não foi possível verificar todos os processos. A operação foi adiada.")) }
        let patterns: [String: [String]] = ["npm": ["npm-cli.js", "npx-cli.js"], "bun": ["/bun install", "/bun add", "/bun update", "bunx "], "gradle": ["GradleDaemon", "GradleWrapperMain", "org.gradle.launcher"], "cocoapods": ["/bin/pod install", "/bin/pod update", "/bin/pod cache"], "pip": ["-m pip install", "/pip install", "/pip3 install"], "uv": ["/uv sync", "/uv pip", "/uv tool", "/uvx "], "homebrew": ["brew.rb install", "brew.rb fetch", "brew.rb upgrade"], "yarn": ["yarn.js", "yarn.cjs", "/yarn install", "/yarn add", "/yarn cache"], "go": ["/go build", "/go test", "/go install", "/go run", "/pkg/tool/"], "ccache": ["/ccache "]]
        for line in ps.output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let processID = Int(parts[0]), processID != getpid() else { continue }
            let command = String(parts[1])
            if let tool, (patterns[tool] ?? []).contains(where: { command.contains($0) }) { found[processID] = CacheCatalog.find(tool)?.name ?? "Ferramenta" }
            if paths.contains(where: { command.contains($0.path + "/") }) { found[processID] = "Ferramenta usando o cache" }
        }
        return found.filter { $0.key > 0 && $0.key != getpid() }.map { BusyProcess(pid: $0.key, name: $0.value) }.sorted { $0.pid < $1.pid }
    }
}

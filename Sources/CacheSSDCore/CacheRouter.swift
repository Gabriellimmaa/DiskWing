import Foundation

public struct RouteDecision: Codable, Sendable {
    public let toolID: String
    public let mode: String
    public let environmentKey: String
    public let path: String?
}

public enum CacheRouter {
    public static func decisions(settings: AppSettings, volumes: [VolumeInfo] = Volumes.list()) -> [RouteDecision] {
        CacheCatalog.all().map { tool in
            guard settings.useExternal, let location = settings.locations[tool.id],
                  let volume = volumes.first(where: { $0.uuid.caseInsensitiveCompare(location.volumeUUID) == .orderedSame }), volume.isWritable,
                  location.relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ Paths.safeComponent(String($0)) }) else {
                return RouteDecision(toolID: tool.id, mode: "local", environmentKey: tool.environmentKey, path: nil)
            }
            let root = URL(fileURLWithPath: volume.path).appendingPathComponent(location.relativePath)
            guard Paths.contains(root, in: URL(fileURLWithPath: volume.path)), root.resolvingSymlinksInPath().path == root.standardizedFileURL.path,
                  FileManager.default.isWritableFile(atPath: root.path) else {
                return RouteDecision(toolID: tool.id, mode: "local", environmentKey: tool.environmentKey, path: nil)
            }
            return RouteDecision(toolID: tool.id, mode: "ssd", environmentKey: tool.environmentKey, path: root.path)
        }
    }
    public static func environment(settings: AppSettings, directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), excluding: Set<String> = []) -> [String: String] {
        Dictionary(uniqueKeysWithValues: decisions(settings: settings).filter { !excluding.contains($0.toolID) && !hasCustomPreference(toolID: $0.toolID, directory: directory) }.compactMap { d in d.path.map { (d.environmentKey, $0) } })
    }
    public static func hasCustomPreference(toolID: String, directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if toolID == "cocoapods", environment["CP_HOME_DIR"] != nil { return true }
        if toolID == "uv", environment["UV_LINK_MODE"] == "symlink" { return true }
        if toolID == "bun", FileManager.default.fileExists(atPath: home.appendingPathComponent(".bun/install/cache/links").path) { return true }
        if ["uv", "pip"].contains(toolID), environment["XDG_CACHE_HOME"] != nil { return true }
        var folders: [URL] = [home]
        var current = directory.standardizedFileURL
        for _ in 0..<40 {
            folders.append(current)
            let parent = current.deletingLastPathComponent()
            if parent == current { break }; current = parent
        }
        var files: [URL] = []
        switch toolID {
        case "npm": files = folders.map { $0.appendingPathComponent(".npmrc") }
        case "bun": files = folders.flatMap { [$0.appendingPathComponent("bunfig.toml"), $0.appendingPathComponent(".bunfig.toml")] }
        case "uv": files = folders.flatMap { [$0.appendingPathComponent("uv.toml"), $0.appendingPathComponent("pyproject.toml")] } + [home.appendingPathComponent(".config/uv/uv.toml")]
        case "pip": files = [home.appendingPathComponent(".pip/pip.conf"), home.appendingPathComponent(".config/pip/pip.conf"), home.appendingPathComponent("Library/Application Support/pip/pip.conf"), URL(fileURLWithPath: "/etc/pip.conf")]; if let venv = environment["VIRTUAL_ENV"] { files.append(URL(fileURLWithPath: venv).appendingPathComponent("pip.conf")) }; if let config = environment["PIP_CONFIG_FILE"] { files.append(URL(fileURLWithPath: config)) }
        case "cocoapods": files = [home.appendingPathComponent(".cocoapods/config.yaml")]
        default: return false
        }
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return true }
            var section = ""
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if line.hasPrefix("#") || line.hasPrefix(";") { continue }
                if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")); continue }
                let key = line.split(whereSeparator: { $0 == "=" || $0 == ":" }).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if toolID == "npm" && key == "cache" { return true }
                if toolID == "bun" && section == "install.cache" && ["dir", "disable"].contains(key) { return true }
                if toolID == "bun" && section == "install" && ["backend", "globalstore"].contains(key) { return true }
                if toolID == "uv" && ["cache-dir", "no-cache"].contains(key) && (file.lastPathComponent != "pyproject.toml" || section == "tool.uv") { return true }
                if toolID == "uv" && key == "link-mode" && line.contains("symlink") && (file.lastPathComponent != "pyproject.toml" || section.hasPrefix("tool.uv")) { return true }
                if toolID == "pip" && ["cache-dir", "no-cache-dir"].contains(key) { return true }
                if toolID == "cocoapods" && key == "cache_root" { return true }
            }
        }
        return false
    }
}

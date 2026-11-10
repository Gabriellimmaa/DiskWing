import Foundation
import Darwin

public struct RouteDecision: Codable, Sendable {
    public let toolID: String
    public let mode: String
    public let environmentKey: String
    public let path: String?
}

public enum CacheRouter {
    public static func commandExclusions(_ arguments: [String]) -> Set<String> {
        var result = Set<String>()
        let isGoCommand = arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent == "go" } ?? false
        for raw in arguments {
            let value = raw.lowercased()
            if value.hasPrefix("--backend") || value.hasPrefix("--global-store") { result.insert("bun") }
            if value.hasPrefix("--link-mode") { result.insert("uv") }
            if ["--cache-folder", "--cachefolder", "--use-yarnrc", "--no-default-rc", "--cwd", "--enable-pnp", "--pnp"].contains(where: { value == $0 || value.hasPrefix($0 + "=") }) { result.insert("yarn") }
            if isGoCommand && (raw == "-C" || raw.hasPrefix("-C=")) { result.insert("go") }
            if ["--dir", "--config-path", "--set-config", "--set", "--directory"].contains(where: { value == $0 || value.hasPrefix($0 + "=") }) || raw == "-d" || raw.hasPrefix("-d/") || raw == "-o" { result.insert("ccache") }
            if value.hasPrefix("gocache=") || value.hasPrefix("goenv=") || value.hasPrefix("gocacheprog=") { result.insert("go") }
            if value.hasPrefix("cache_dir=") || value.hasPrefix("ccache_") && value.contains("=") { result.insert("ccache") }
            if value.hasPrefix("yarn_") && value.contains("=") { result.insert("yarn") }
            if value.hasPrefix("--") {
                let option = String(value.dropFirst(2).split(separator:"=",maxSplits:1).first ?? "")
                if !option.isEmpty && ["userconfig","globalconfig","prefix","cache"].contains(where: { $0.hasPrefix(option) || option.hasPrefix($0) }) { result.insert("npm") }
            } else if raw.hasPrefix("-"), raw.contains("C") { result.insert("npm") }
        }
        return result
    }
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
    public static func environment(settings: AppSettings, directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), excluding: Set<String> = [], volumes: [VolumeInfo]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, processEnvironment: [String:String] = ProcessInfo.processInfo.environment, npmGlobalConfigurations: [URL]? = nil, pipGlobalConfigurations: [URL]? = nil) -> [String: String] {
        Dictionary(uniqueKeysWithValues: decisions(settings: settings, volumes: volumes ?? Volumes.list()).filter {
            !excluding.contains($0.toolID) && !hasCustomPreference(toolID: $0.toolID, directory: directory, home: home, processEnvironment: processEnvironment, npmGlobalConfigurations: npmGlobalConfigurations, pipGlobalConfigurations: pipGlobalConfigurations) &&
            processEnvironment[$0.environmentKey] == nil &&
            !($0.toolID == "npm" && processEnvironment["NPM_CONFIG_CACHE"] != nil)
        }.compactMap { d in d.path.map { (d.environmentKey, $0) } })
    }
    public static func hasCustomPreference(toolID: String, directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, processEnvironment environment: [String:String] = ProcessInfo.processInfo.environment, npmGlobalConfigurations: [URL]? = nil, pipGlobalConfigurations: [URL]? = nil) -> Bool {
        if let tool = CacheCatalog.find(toolID, home: home), environment[tool.environmentKey] != nil { return true }
        if toolID == "npm", environment.keys.contains(where: { ["npm_config_cache", "npm_config_userconfig", "npm_config_globalconfig", "npm_config_prefix"].contains($0.lowercased()) }) { return true }
        if ["pip","uv"].contains(toolID), environment["XDG_CONFIG_HOME"] != nil { return true }
        if toolID == "pip", ["XDG_DATA_HOME","XDG_DATA_DIRS","PIP_CONFIG_FILE"].contains(where: { environment[$0] != nil }) { return true }
        if toolID == "cocoapods", environment["CP_HOME_DIR"] != nil { return true }
        if toolID == "uv", environment["UV_LINK_MODE"] == "symlink" { return true }
        if toolID == "bun", FileManager.default.fileExists(atPath: home.appendingPathComponent(".bun/install/cache/links").path) { return true }
        if ["uv", "pip"].contains(toolID), environment["XDG_CACHE_HOME"] != nil { return true }
        if toolID == "yarn" {
            // Do not send PnP or an upgraded Yarn runtime to a cache chosen for Classic.
            guard CacheAdapters.yarnClassicVersion(home: home) != nil else { return true }
            if environment.keys.contains(where: { ["yarn_cache_folder", "yarn_rc_filename", "yarn_ignore_path", "yarn_plugnplay_override", "npm_config_cache", "npm_config_userconfig", "npm_config_globalconfig"].contains($0.lowercased()) }) { return true }
            if environment["XDG_CACHE_HOME"] != nil { return true }
        }
        if toolID == "go", ["GOENV", "GOCACHEPROG"].contains(where: { environment[$0] != nil }) { return true }
        if toolID == "ccache", ["CCACHE_CONFIGPATH", "CCACHE_CONFIGDIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"].contains(where: { environment[$0] != nil }) { return true }
        guard directory.isFileURL else { return true }
        var folders: [URL] = [home]
        var current = directory.standardizedFileURL, reachedRoot = false
        for _ in 0..<40 {
            folders.append(current)
            // Foundation URL equality at the filesystem root differs across
            // supported macOS versions. Stop at the actual path, not URL identity.
            if current.path == "/" { reachedRoot = true; break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }; current = parent
        }
        guard reachedRoot else { return true } // Never assume unvisited ancestor configuration is absent.
        var files: [URL] = []
        switch toolID {
        case "npm":
            files = folders.map { $0.appendingPathComponent(".npmrc") }
            if let configured = npmGlobalConfigurations { files += configured }
            else {
                files += [URL(fileURLWithPath:"/opt/homebrew/etc/npmrc"), URL(fileURLWithPath:"/usr/local/etc/npmrc")]
                if let npm = ToolLocator.locate("npm", home: home) {
                    files.append(npm.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("etc/npmrc"))
                    files.append(npm.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("npmrc"))
                }
            }
        case "bun": files = folders.flatMap { [$0.appendingPathComponent("bunfig.toml"), $0.appendingPathComponent(".bunfig.toml")] }
        case "uv": files = folders.flatMap { [$0.appendingPathComponent("uv.toml"), $0.appendingPathComponent("pyproject.toml")] } + [home.appendingPathComponent(".config/uv/uv.toml")]
        case "pip": files = [home.appendingPathComponent(".pip/pip.conf"), home.appendingPathComponent(".config/pip/pip.conf"), home.appendingPathComponent("Library/Application Support/pip/pip.conf")] + (pipGlobalConfigurations ?? [URL(fileURLWithPath:"/Library/Application Support/pip/pip.conf"), URL(fileURLWithPath:"/etc/pip.conf")]); if let venv = environment["VIRTUAL_ENV"] { files.append(URL(fileURLWithPath: venv).appendingPathComponent("pip.conf")) }; if let config = environment["PIP_CONFIG_FILE"] { files.append(URL(fileURLWithPath: config)) }
        case "cocoapods": files = [home.appendingPathComponent(".cocoapods/config.yaml")]
        case "yarn":
            for folder in folders {
                if [".yarnrc.yml", ".pnp.js", ".pnp.cjs"].contains(where: { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) { return true }
            }
            files = folders.flatMap { [$0.appendingPathComponent(".yarnrc"), $0.appendingPathComponent(".npmrc"), $0.appendingPathComponent("package.json")] }
        case "go": files = [home.appendingPathComponent("Library/Application Support/go/env"), home.appendingPathComponent(".config/go/env")]
        case "ccache": files = [home.appendingPathComponent(".ccache/ccache.conf"), home.appendingPathComponent("Library/Caches/ccache/ccache.conf"), home.appendingPathComponent("Library/Preferences/ccache/ccache.conf"), home.appendingPathComponent(".config/ccache/ccache.conf"), URL(fileURLWithPath: "/opt/homebrew/etc/ccache.conf"), URL(fileURLWithPath: "/usr/local/etc/ccache.conf"), URL(fileURLWithPath: "/etc/ccache.conf")]
        default: return false
        }
        for file in Set(files) {
            var info = stat()
            if lstat(file.path, &info) != 0 { if errno == ENOENT { continue }; return true }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_flags & UInt32(SF_DATALESS) == 0, info.st_size <= 1_048_576 else { return true }
            let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { return true }
            var opened = stat()
            guard fstat(fd,&opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino,
                  opened.st_mode & S_IFMT == S_IFREG, opened.st_flags & UInt32(SF_DATALESS) == 0, opened.st_size <= 1_048_576 else { close(fd); return true }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            let data = try? handle.read(upToCount: 1_048_577); try? handle.close()
            guard let data, data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else { return true }
            if toolID == "yarn", file.lastPathComponent == "package.json" {
                guard let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return true }
                if let manager = manifest["packageManager"] as? String, manager.hasPrefix("yarn@"), !manager.hasPrefix("yarn@1.") { return true }
                if let install = manifest["installConfig"] as? [String: Any], install["pnp"] as? Bool == true { return true }
                continue
            }
            var section = ""
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if line.hasPrefix("#") || line.hasPrefix(";") { continue }
                if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")); continue }
                let key = line.split(whereSeparator: { $0 == "=" || $0 == ":" }).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if toolID == "npm" && ["cache", "userconfig", "globalconfig", "prefix"].contains(key) { return true }
                if toolID == "bun" && section == "install.cache" && ["dir", "disable"].contains(key) { return true }
                if toolID == "bun" && section == "install" && ["backend", "globalstore"].contains(key) { return true }
                if toolID == "uv" && ["cache-dir", "no-cache"].contains(key) && (file.lastPathComponent != "pyproject.toml" || section == "tool.uv") { return true }
                if toolID == "uv" && key == "link-mode" && line.contains("symlink") && (file.lastPathComponent != "pyproject.toml" || section.hasPrefix("tool.uv")) { return true }
                if toolID == "pip" && ["cache-dir", "no-cache-dir"].contains(key) { return true }
                if toolID == "cocoapods" && key == "cache_root" { return true }
                if toolID == "yarn" && ["cache-folder", "cache_folder", "yarn-path", "plugnplay", "pnp", "use-yarnrc", "userconfig", "globalconfig"].contains(where: { line.contains($0) }) { return true }
                if toolID == "yarn", file.lastPathComponent == ".npmrc", key == "cache" { return true }
                if toolID == "go" && ["gocache", "gocacheprog"].contains(key) { return true }
                if toolID == "ccache" && key == "cache_dir" { return true }
            }
        }
        return false
    }
}

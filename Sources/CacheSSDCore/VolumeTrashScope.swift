import Foundation
import Darwin

/// A reviewed selection belongs to one filesystem, even when the explorer shows
/// an APFS group. Paths are rebuilt from the volume UUID, never a stale mount name.
public struct VolumeTrashScope: Codable, Sendable {
    public let schemaVersion: Int
    public let volumeUUID: String
    public let originalMountPath: String
    public let mountRootIdentity: FileIdentity
    public let relativePath: String
    public let itemIdentity: FileIdentity
    public let reviewedPath: String

    public init(item: URL, volume: VolumeInfo, expectedIdentity: FileIdentity? = nil) throws {
        let mount = URL(fileURLWithPath: volume.path, isDirectory: true)
        guard !volume.uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              volume.isWritable, Self.unredirected(mount, allowingMissing: false),
              let scoped = Self.scoped(item, within: mount),
              let relative = Self.relative(scoped, within: mount), !relative.isEmpty,
              Self.unredirected(item, allowingMissing: false) else { throw Self.failure() }
        let root = try FileIdentity(mount), identity = try FileIdentity(item)
        guard identity.device == root.device, expectedIdentity == nil || expectedIdentity == identity else { throw Self.failure() }
        schemaVersion = 1; volumeUUID = volume.uuid; originalMountPath = mount.path
        mountRootIdentity = root; relativePath = relative; itemIdentity = identity; reviewedPath = item.path
    }

    /// Active operations require the reviewed mount instance. A recovery may
    /// accept a remounted device only with the same UUID/root inode and digest.
    public func resolve(volumeProvider: (String) -> VolumeInfo? = { Volumes.find(uuid: $0) }, forRecovery: Bool = false, requireItem: Bool = true) throws -> URL {
        let (volume, mount) = try resolvedVolume(volumeProvider: volumeProvider, forRecovery: forRecovery)
        let raw = mount.appendingPathComponent(relativePath)
        guard Self.unredirected(raw, allowingMissing: !requireItem) else { throw Self.failure() }
        let item = Self.finderPath(raw)
        if requireItem {
            let identity = try FileIdentity(item)
            guard identity.device == (try FileIdentity(mount)).device,
                  identity.inode == itemIdentity.inode,
                  forRecovery || identity == itemIdentity else { throw Self.failure() }
        }
        guard volume.isWritable else { throw Self.failure() }
        return item
    }

    func resolvedVolume(volumeProvider: (String) -> VolumeInfo?, forRecovery: Bool = false) throws -> (VolumeInfo, URL) {
        guard schemaVersion == 1, !volumeUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Self.safeRelative(relativePath), !relativePath.isEmpty,
              let volume = volumeProvider(volumeUUID), volume.uuid.caseInsensitiveCompare(volumeUUID) == .orderedSame,
              volume.isWritable else { throw Self.failure() }
        let mount = URL(fileURLWithPath: volume.path, isDirectory: true)
        guard Self.unredirected(mount, allowingMissing: false) else { throw Self.failure() }
        let identity = try FileIdentity(mount)
        guard identity.inode == mountRootIdentity.inode,
              forRecovery || identity.device == mountRootIdentity.device else { throw Self.failure() }
        var metadata = stat()
        guard lstat(mount.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else { throw Self.failure() }
        return (volume, mount)
    }

    func trashURL(relative: String, volumeProvider: (String) -> VolumeInfo?) throws -> URL {
        let (_, mount) = try resolvedVolume(volumeProvider: volumeProvider, forRecovery: true)
        guard Self.safeRelative(relative), !relative.isEmpty else { throw Self.failure() }
        let raw = mount.appendingPathComponent(relative)
        guard Self.unredirected(raw, allowingMissing: false) else { throw Self.failure() }
        let result = Self.finderPath(raw), identity = try FileIdentity(result)
        guard identity.device == (try FileIdentity(mount)).device else { throw Self.failure() }
        return result
    }

    func relativeTrashPath(_ item: URL, volumeProvider: (String) -> VolumeInfo?) throws -> String {
        let (_, mount) = try resolvedVolume(volumeProvider: volumeProvider)
        guard let scoped = Self.scoped(item, within: mount), let relative = Self.relative(scoped, within: mount),
              !relative.isEmpty, Self.unredirected(item, allowingMissing: false),
              (try FileIdentity(item)).device == (try FileIdentity(mount)).device else { throw Self.failure() }
        return relative
    }

    static func safeRelative(_ path: String) -> Bool {
        !path.hasPrefix("/") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0")
        }
    }
    static func relative(_ item: URL, within mount: URL) -> String? {
        let root = mount.path == "/" ? "/" : mount.path + "/"
        guard item.path.hasPrefix(root) else { return item.path == mount.path ? "" : nil }
        let value = String(item.path.dropFirst(root.count))
        return safeRelative(value) ? value : nil
    }
    static func scoped(_ item: URL, within mount: URL) -> URL? {
        if relative(item, within: mount) != nil { return item }
        return DataVolumePaths.scopedScanEntry(item, within: mount)
    }
    static func unredirected(_ item: URL, allowingMissing: Bool) -> Bool {
        guard item.isFileURL else { return false }
        let parts = Array(item.pathComponents.dropFirst())
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for (index, component) in parts.enumerated() {
            guard component != ".", component != "..", !component.contains("\0") else { return false }
            current.appendPathComponent(component)
            var metadata = stat()
            if lstat(current.path, &metadata) != 0 { return allowingMissing && errno == ENOENT && index == parts.count - 1 }
            if metadata.st_mode & S_IFMT == S_IFLNK { return false }
            if index < parts.count - 1 && metadata.st_mode & S_IFMT != S_IFDIR { return false }
        }
        return true
    }
    /// Finder and URL enumeration can shorten the Data spelling. Use that
    /// spelling only when both existing parents identify the same directory.
    static func finderPath(_ item: URL) -> URL {
        let prefix = DataVolumePaths.dataRoot.path + "/"
        guard item.path.hasPrefix(prefix) else { return item }
        let candidate = URL(fileURLWithPath: "/" + item.path.dropFirst(prefix.count))
        let left = item.deletingLastPathComponent(), right = candidate.deletingLastPathComponent()
        guard unredirected(left, allowingMissing: false), unredirected(right, allowingMissing: false),
              let leftIdentity = try? FileIdentity(left), let rightIdentity = try? FileIdentity(right),
              leftIdentity.device == rightIdentity.device, leftIdentity.inode == rightIdentity.inode else { return item }
        var a = stat(), b = stat()
        if lstat(item.path, &a) == 0 {
            guard lstat(candidate.path, &b) == 0, a.st_dev == b.st_dev, a.st_ino == b.st_ino,
                  a.st_mode & S_IFMT != S_IFLNK, b.st_mode & S_IFMT != S_IFLNK else { return item }
        } else { guard errno == ENOENT else { return item } }
        return candidate
    }
    static func failure() -> Error { CacheSSDError.message(L10n.text("O volume ou o item mudou desde a revisão. Analise novamente antes de continuar.")) }

    /// Other filesystems remain disabled until actual Finder Trash/restore
    /// qualification exists. Callers may inject an explicitly qualified policy.
    public static func qualifiedFinderTrash(_ volume: VolumeInfo) -> Bool {
        var info = statfs()
        guard volume.isWritable, statfs(volume.path, &info) == 0 else { return false }
        let type = withUnsafePointer(to: &info.f_fstypename) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
        return ["apfs", "hfs"].contains(type.lowercased())
    }
}

extension PersonalActionPolicy {
    public static func reasonPreventingTrash(_ url: URL, on volume: VolumeInfo, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                            storeBase: URL? = nil, protectedRoots: [URL] = []) -> String? {
        let mount = URL(fileURLWithPath: volume.path, isDirectory: true)
        guard volume.isWritable, VolumeTrashScope.unredirected(mount, allowingMissing: false),
              VolumeTrashScope.unredirected(url, allowingMissing: true),
              let scoped = VolumeTrashScope.scoped(url, within: mount),
              let relative = VolumeTrashScope.relative(scoped, within: mount), !relative.isEmpty else {
            return "Raízes, links e volumes indisponíveis são preservados. Selecione um item real do volume analisado."
        }
        let item = VolumeTrashScope.finderPath(url)
        let canonicalHome = VolumeTrashScope.finderPath(home)
        let insideHome = Paths.contains(item, in: canonicalHome)
        if insideHome, let reason = reasonPreventingTrash(item, home: canonicalHome, storeBase: storeBase) { return reason }
        let roots = [storeBase ?? Paths.support, Paths.support, mount.appendingPathComponent("MacCaches/CacheSSD")] + protectedRoots
        func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
            let a = lhs.standardizedFileURL.path.lowercased(), b = rhs.standardizedFileURL.path.lowercased()
            return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
        }
        for root in roots {
            let values = [root, Paths.physicalURL(root), VolumeTrashScope.finderPath(root)] + (DataVolumePaths.alias(of: root).map { [$0] } ?? [])
            if values.contains(where: { overlaps(item, $0) || overlaps(scoped, $0) }) { return "Os registros, caches gerenciados e cópias de recuperação do DiskWing são preservados." }
        }
        let parts = relative.split(separator: "/").map { $0.lowercased() }
        let system: Set<String> = ["system", "private", "usr", "bin", "sbin", "etc", "var", "dev", "library", "applications", "volumes"]
        if !insideHome, let first = parts.first, system.contains(first) { return "Esta seleção pertence a uma área estrutural, do sistema ou de aplicativos instalados." }
        if parts.first == "users", parts.count <= 2 { return "Esta é uma pasta estrutural. Abra-a e selecione um item específico para revisar." }
        let sensitive: Set<String> = [".trash", ".trashes", ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".codex", ".git", ".hg", ".svn", ".netrc", ".npmrc", ".pypirc", ".git-credentials", "id_rsa", "id_ed25519", "id_ecdsa", "node_modules", ".venv", "venv", "site-packages", ".android", ".rustup", ".sdkman", ".nvm", ".pyenv", ".rbenv"]
        if parts.contains(where: { sensitive.contains($0) || $0 == ".env" || $0.hasPrefix(".env.") }) { return "Esta seleção contém credenciais, perfis, SDKs ou instalações que precisam ser preservados." }
        let patterns = ["Library/Keychains", "Library/Accounts", "Library/Safari", "Library/Containers/com.apple.Safari", "Library/Containers/com.apple.Passwords", "Library/Group Containers/group.com.apple.safari", "Library/Group Containers/group.com.apple.Passwords", "Library/Application Support/Google/Chrome", "Library/Application Support/Chromium", "Library/Application Support/Microsoft Edge", "Library/Application Support/BraveSoftware/Brave-Browser", "Library/Application Support/Firefox", "Library/Developer/CoreSimulator", "Library/Android", ".config/gcloud", ".config/gh", ".bun/install/cache", ".cache/uv", ".local/share/uv", ".npm/_npx", ".gradle/jdks", ".gradle/wrapper", ".cargo/bin", "MacCaches/CacheSSD"]
        for pattern in patterns {
            let components = pattern.lowercased().split(separator: "/").map(String.init)
            if parts.count >= components.count, (0...(parts.count - components.count)).contains(where: { Array(parts[$0..<($0 + components.count)]) == components }) { return "Esta seleção contém credenciais, perfis, SDKs ou instalações que precisam ser preservados." }
        }
        let packages: Set<String> = ["app", "photoslibrary", "photolibrary", "sparsebundle", "pvm", "utm", "vmwarevm", "framework", "kext"]
        if parts.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension) }) { return "Bibliotecas e pacotes precisam de um procedimento específico." }
        var metadata = stat()
        if lstat(item.path, &metadata) == 0 {
            guard let root = try? FileIdentity(mount), Int64(metadata.st_dev) == root.device else { return "A seleção contém outro volume montado. Analise esse volume separadamente." }
            if let reason = trashMetadataReason(metadata) { return reason }
        } else if errno != ENOENT { return "Não foi possível examinar este item. A origem será preservada." }
        if let values = try? item.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
        return nil
    }

    public static func trashWarning(_ url: URL, on volume: VolumeInfo, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        trashWarning(VolumeTrashScope.finderPath(url), home: home) ?? "Este item será enviado à Lixeira do próprio volume. Dados desconhecidos podem ser importantes; revise o conteúdo antes de confirmar."
    }

    static func validateVolumeTrashTree(_ source: URL, volume: VolumeInfo, home: URL, storeBase: URL, protectedRoots: [URL],
                                       cancellation: CancellationFlag, maxEntries: Int = 1_000_000, progress: (String) -> Void) throws {
        guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
        if let reason = reasonPreventingTrash(source, on: volume, home: home, storeBase: storeBase, protectedRoots: protectedRoots) { throw CacheSSDError.message(reason) }
        var root = stat()
        guard lstat(source.path, &root) == 0 else { throw VolumeTrashScope.failure() }
        if root.st_mode & S_IFMT != S_IFDIR { return }
        var failed = false, count = 0, finished = false
        guard let entries = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw VolumeTrashScope.failure() }
        while !finished {
            try autoreleasepool {
                for _ in 0..<256 {
                    guard let child = entries.nextObject() as? URL else { finished = true; break }
                    guard !cancellation.isCancelled, count < maxEntries else { throw CacheSSDError.message(L10n.text("A inspeção foi cancelada ou excedeu o limite. A origem foi preservada.")) }
                    if let reason = reasonPreventingTrash(child, on: volume, home: home, storeBase: storeBase, protectedRoots: protectedRoots) { throw CacheSSDError.message(reason) }
                    var info = stat()
                    guard lstat(child.path, &info) == 0, info.st_dev == root.st_dev else { throw VolumeTrashScope.failure() }
                    count += 1
                    if count % 200 == 0 { progress("Inspecionando \(count) itens…") }
                }
            }
        }
        guard !failed else { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
    }
}

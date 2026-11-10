import Foundation
import CryptoKit
import Darwin

public struct ManifestEntry: Codable, Equatable {
    public let path: String
    public let kind: String
    public let size: Int64
    public let digest: String
    public var metadata: String = ""
}

public struct FileMeasurement: Sendable {
    public var logical: Int64 = 0
    public var allocated: Int64 = 0
    public var entries = 0
    public var unreadablePaths: [String] = []
    public var missing = false
    public var isComplete: Bool { !missing && unreadablePaths.isEmpty }
}

public enum FileTree {
    public static func measure(_ root: URL) -> FileMeasurement {
        var result = FileMeasurement(), rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else {
            if errno == ENOENT { result.missing = true } else { result.unreadablePaths = [root.path] }
            return result
        }
        if rootInfo.st_mode & S_IFMT == S_IFREG {
            result.logical = Int64(rootInfo.st_size); result.allocated = Int64(rootInfo.st_blocks) * 512; result.entries = 1
            return result
        }
        guard rootInfo.st_mode & S_IFMT == S_IFDIR else { result.unreadablePaths = [root.path]; return result }
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { url, _ in result.unreadablePaths.append(url.path); return true }) else {
            result.unreadablePaths.append(root.path); return result
        }
        var seen = Set<String>()
        for case let url as URL in e {
            result.entries += 1
            var s = stat()
            guard lstat(url.path, &s) == 0 else { result.unreadablePaths.append(url.path); continue }
            if s.st_dev != rootInfo.st_dev { result.unreadablePaths.append(url.path); e.skipDescendants(); continue }
            if (s.st_mode & S_IFMT) == S_IFLNK { continue }
            if (s.st_mode & S_IFMT) == S_IFREG {
                result.logical += Int64(s.st_size)
                if seen.insert("\(s.st_dev):\(s.st_ino)").inserted { result.allocated += Int64(s.st_blocks) * 512 }
            }
        }
        return result
    }

    public static func manifest(_ root: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws -> [ManifestEntry] {
        let root = Paths.physicalURL(root)
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw CacheSSDError.message(L10n.text("A origem não é uma pasta disponível.")) }
        var enumerationFailed = false
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível enumerar o cache.")) }
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else { throw CacheSSDError.message(L10n.text("A origem está indisponível.")) }
        var entries: [ManifestEntry] = []
        for case let url as URL in e {
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada. A origem foi preservada.")) }
            guard url.path.hasPrefix(root.path + "/") else { throw CacheSSDError.message(L10n.text("O caminho enumerado não pertence à origem.")) }
            let rel = String(url.path.dropFirst(root.path.count + 1))
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { continue }
            var s = stat()
            guard lstat(url.path, &s) == 0 else { throw CacheSSDError.message(L10n.text("Um arquivo mudou durante a leitura. Tente novamente com a ferramenta fechada.")) }
            guard s.st_dev == rootInfo.st_dev else { throw CacheSSDError.message(L10n.text("A origem contém outro volume montado e foi preservada.")) }
            switch s.st_mode & S_IFMT {
            case S_IFDIR: entries.append(ManifestEntry(path: rel, kind: "directory", size: 0, digest: "", metadata: try metadataDigest(url)))
            case S_IFLNK:
                let target = try linkTarget(url, root: root, tool: tool)
                entries.append(ManifestEntry(path: rel, kind: "link", size: 0, digest: target))
            case S_IFREG:
                let cloud = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if cloud?.isUbiquitousItem == true && cloud?.ubiquitousItemDownloadingStatus != .current { throw CacheSSDError.message(L10n.text("Há conteúdo da nuvem ainda não baixado. A origem será preservada.")) }
                if entries.count % 200 == 0 { progress("Conferindo \(entries.count) itens…") }
                entries.append(ManifestEntry(path: rel, kind: "file", size: Int64(s.st_size), digest: try hash(url, cancellation: cancellation), metadata: try metadataDigest(url)))
            default: throw CacheSSDError.message(L10n.text("O cache contém um arquivo especial em uso; a migração foi adiada."))
            }
        }
        if enumerationFailed { throw CacheSSDError.message(L10n.text("A leitura ficou incompleta por falta de acesso. Nenhum conteúdo será liberado.")) }
        return entries.sorted { $0.path < $1.path }
    }

    public static func hash(_ url: URL, cancellation: CancellationFlag = CancellationFlag()) throws -> String {
        var initial = stat()
        guard lstat(url.path, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG, initial.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message(L10n.text("O arquivo não está disponível localmente.")) }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CacheSSDError.message(L10n.text("O arquivo mudou ou não permite leitura.")) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == initial.st_dev, opened.st_ino == initial.st_ino, opened.st_mode & S_IFMT == S_IFREG, opened.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message(L10n.text("O arquivo mudou durante a leitura.")) }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada.")) }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func copy(_ source: URL, to target: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws {
        let source = Paths.physicalURL(source)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw CacheSSDError.message(L10n.text("O destino já existe. Nenhum arquivo foi sobrescrito.")) }
        try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var enumerationFailed = false
        guard let e = fm.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível ler a origem.")) }
        var rootInfo = stat()
        guard lstat(source.path, &rootInfo) == 0 else { throw CacheSSDError.message(L10n.text("A origem está indisponível.")) }
        var count = 0
        var directories: [(URL, URL)] = [(source, target)]
        for case let url as URL in e {
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { continue }
            guard url.path.hasPrefix(source.path + "/") else { throw CacheSSDError.message(L10n.text("O caminho de cópia não pertence à origem.")) }
            let rel = String(url.path.dropFirst(source.path.count + 1)), dest = target.appendingPathComponent(rel)
            var s = stat()
            guard lstat(url.path, &s) == 0 else { throw CacheSSDError.message(L10n.text("A origem mudou durante a cópia.")) }
            guard s.st_dev == rootInfo.st_dev else { throw CacheSSDError.message(L10n.text("A origem contém outro volume montado.")) }
            if (s.st_mode & S_IFMT) == S_IFDIR {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                directories.append((url, dest))
            } else if s.st_mode & S_IFMT == S_IFLNK {
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: linkTarget(url, root: source, tool: tool))
            } else {
                guard s.st_mode & S_IFMT == S_IFREG || s.st_mode & S_IFMT == S_IFLNK else { throw CacheSSDError.message(L10n.text("Arquivos especiais não são copiados.")) }
                try fm.copyItem(at: url, to: dest)
            }
            count += 1
            if count % 200 == 0 { progress("Copiando \(count) itens…") }
        }
        if enumerationFailed { throw CacheSSDError.message(L10n.text("A cópia ficou incompleta por falta de acesso. A origem foi preservada.")) }
        for (from, to) in directories.reversed() {
            guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)) == 0 else {
                throw CacheSSDError.message(L10n.text("Não foi possível preservar os metadados da pasta. A origem foi mantida."))
            }
        }
    }

    public static func copyItem(_ source: URL, to target: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws {
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw CacheSSDError.message(L10n.text("A origem está indisponível.")) }
        if info.st_mode & S_IFMT == S_IFDIR { try copy(source, to: target, tool: tool, cancellation: cancellation, progress: progress) }
        else {
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
            _ = try digest(source, tool: tool, cancellation: cancellation)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw CacheSSDError.message(L10n.text("O destino já existe.")) }
            try FileManager.default.copyItem(at: source, to: target)
        }
    }

    public static func digest(_ root: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag()) throws -> String {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { throw CacheSSDError.message(L10n.text("A origem está indisponível ou foi redirecionada.")) }
        var data = Data((try metadataDigest(root)).utf8)
        if info.st_mode & S_IFMT == S_IFDIR {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            data.append(try encoder.encode(manifest(root, tool: tool, cancellation: cancellation)))
        } else if info.st_mode & S_IFMT == S_IFREG {
            let cloud = try root.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard cloud.isUbiquitousItem != true || cloud.ubiquitousItemDownloadingStatus == .current else { throw CacheSSDError.message(L10n.text("Baixe o arquivo no Finder antes de movê-lo.")) }
            data.append(Data(try hash(root, cancellation: cancellation).utf8))
        } else { throw CacheSSDError.message(L10n.text("Arquivos especiais não podem receber esta operação.")) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Copy-relevant metadata; access times and filesystem compression are not content.
    public static func metadataDigest(_ url: URL) throws -> String {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível conferir os metadados.")) }
        guard info.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message(L10n.text("O arquivo não está disponível localmente.")) }
        var components = [String(info.st_mode & 0o777), "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"]
        let length = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard length >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível ler atributos do arquivo.")) }
        if length > 0 {
            var names = [CChar](repeating: 0, count: length)
            guard listxattr(url.path, &names, length, XATTR_NOFOLLOW) == length else { throw CacheSSDError.message(L10n.text("Os atributos mudaram durante a leitura.")) }
            let strings = names.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }.sorted()
            for name in strings where name != "com.apple.decmpfs" && name != "com.apple.lastuseddate#PS" {
                let count = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
                guard count >= 0, count <= 16_777_216 else { throw CacheSSDError.message(L10n.text("O atributo está indisponível ou excede o limite desta versão. A origem foi preservada.")) }
                var data = [UInt8](repeating: 0, count: count)
                guard getxattr(url.path, name, &data, count, 0, XATTR_NOFOLLOW) == count else { throw CacheSSDError.message(L10n.text("Os atributos mudaram durante a leitura.")) }
                components.append(name + ":" + SHA256.hash(data: Data(data)).map { String(format: "%02x", $0) }.joined())
            }
        }
        if let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var count = ssize_t(0)
            if let text = acl_to_text(acl, &count) { components.append(String(cString: text)); acl_free(text) }
            else { throw CacheSSDError.message(L10n.text("Não foi possível conferir as permissões estendidas.")) }
        } else if errno != ENOENT && errno != ENOTSUP { throw CacheSSDError.message(L10n.text("Não foi possível ler as permissões estendidas.")) }
        return SHA256.hash(data: Data(components.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // Bun creates absolute links to packages inside its own cache. Normalize only
    // these verified internal links so a copy never points back to the old disk.
    private static func linkTarget(_ link: URL, root: URL, tool: String) throws -> String {
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        let immediate = target.hasPrefix("/") ? URL(fileURLWithPath: target) : link.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL
        let resolved = immediate.resolvingSymlinksInPath()
        guard Paths.contains(immediate, in: root), Paths.contains(resolved, in: root), FileManager.default.fileExists(atPath: immediate.path), !target.hasPrefix("/") || tool == "bun" else { throw CacheSSDError.message(L10n.text("Este cache contém um link externo e não pode ser migrado por esta versão.")) }
        guard target.hasPrefix("/") else { return target }
        let parent = link.deletingLastPathComponent().pathComponents, child = resolved.pathComponents
        var common = 0
        while common < min(parent.count, child.count), parent[common] == child[common] { common += 1 }
        return (Array(repeating: "..", count: parent.count - common) + child.dropFirst(common)).joined(separator: "/")
    }
}

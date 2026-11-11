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
    public var isCancelled = false
    public var reachedLimit = false
    public var isComplete: Bool { !missing && !isCancelled && !reachedLimit && unreadablePaths.isEmpty }
}

public enum FileTree {
    /// Staging and publication are siblings; RENAME_EXCL closes the reappearance race.
    static func publishWithoutReplacing(_ source: URL, to target: URL) throws {
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível publicar a cópia sem substituir arquivos. As cópias foram preservadas.")) }
    }
    public static func validateDestination(_ directory: URL) throws {
        guard (try directory.resourceValues(forKeys: [.volumeSupportsExtendedSecurityKey])).volumeSupportsExtendedSecurity == true else { throw CacheSSDError.message(L10n.text("O destino não oferece as permissões necessárias para preservar os metadados. Escolha um volume compatível, como APFS.")) }
    }
    private enum MeasurementStop: Error { case stopped }
    public static func measure(_ root: URL, cancellation: CancellationFlag = CancellationFlag(), maxEntries: Int = 1_000_000, progress: (String) -> Void = { _ in }) -> FileMeasurement {
        var result = FileMeasurement(), rootInfo = stat()
        guard !cancellation.isCancelled else { result.isCancelled = true; return result }
        guard maxEntries > 0 else { result.reachedLimit = true; return result }
        guard lstat(root.path, &rootInfo) == 0 else {
            if errno == ENOENT { result.missing = true } else { result.unreadablePaths = [root.path] }
            return result
        }
        if rootInfo.st_mode & S_IFMT == S_IFREG {
            result.logical = Int64(rootInfo.st_size); result.allocated = Int64(rootInfo.st_blocks) * 512; result.entries = 1
            return result
        }
        guard rootInfo.st_mode & S_IFMT == S_IFDIR else { result.unreadablePaths = [root.path]; return result }
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { url, _ in if result.unreadablePaths.count < 200 { result.unreadablePaths.append(url.path) }; return true }) else {
            result.unreadablePaths.append(root.path); return result
        }
        var seen = Set<String>()
        try? enumerate(e) { url in
            if cancellation.isCancelled { result.isCancelled = true; throw MeasurementStop.stopped }
            if result.entries >= maxEntries { result.reachedLimit = true; throw MeasurementStop.stopped }
            result.entries += 1
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { if result.unreadablePaths.count < 200 { result.unreadablePaths.append(url.path) }; return }
            if metadata.st_dev != rootInfo.st_dev { if result.unreadablePaths.count < 200 { result.unreadablePaths.append(url.path) }; if metadata.st_mode & S_IFMT == S_IFDIR { e.skipDescendants() }; return }
            if metadata.st_mode & S_IFMT == S_IFREG {
                result.logical += Int64(metadata.st_size)
                if metadata.st_nlink <= 1 || seen.insert("\(metadata.st_dev):\(metadata.st_ino)").inserted { result.allocated += Int64(metadata.st_blocks) * 512 }
            }
            if result.entries % 200 == 0 { progress("Medindo \(result.entries) itens…") }
        }
        result.isCancelled = result.isCancelled || cancellation.isCancelled
        return result
    }

    private static func enumerate(_ enumerator: FileManager.DirectoryEnumerator, visit: (URL) throws -> Void) throws {
        var finished = false
        while !finished {
            try autoreleasepool {
                for _ in 0..<256 {
                    guard let url = enumerator.nextObject() as? URL else { finished = true; break }
                    try visit(url)
                }
            }
        }
    }

    public static func manifest(_ root: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws -> [ManifestEntry] {
        var entries: [ManifestEntry] = []
        try visitManifest(root, tool: tool, cancellation: cancellation, progress: progress) { entries.append($0) }
        return entries.sorted { $0.path < $1.path }
    }

    private static func visitManifest(_ requested: URL, tool: String, cancellation: CancellationFlag, progress: (String) -> Void, visit: (ManifestEntry) throws -> Void) throws {
        let root = Paths.physicalURL(requested)
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message(L10n.text("A origem não é uma pasta disponível.")) }
        var failed = false, count = 0
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível enumerar o cache.")) }
        let prefix = root.path == "/" ? "/" : root.path + "/"
        try enumerate(e) { url in
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada. A origem foi preservada.")) }
            guard url.path.hasPrefix(prefix) else { throw CacheSSDError.message(L10n.text("O caminho enumerado não pertence à origem.")) }
            let rel = String(url.path.dropFirst(prefix.count))
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { return }
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { throw CacheSSDError.message(L10n.text("Um arquivo mudou durante a leitura. Tente novamente com a ferramenta fechada.")) }
            guard metadata.st_dev == info.st_dev else { throw CacheSSDError.message(L10n.text("A origem contém outro volume montado e foi preservada.")) }
            let entry: ManifestEntry
            switch metadata.st_mode & S_IFMT {
            case S_IFDIR: entry = ManifestEntry(path: rel, kind: "directory", size: 0, digest: "", metadata: try metadataDigest(url))
            case S_IFLNK: entry = ManifestEntry(path: rel, kind: "link", size: 0, digest: try linkTarget(url, root: root, tool: tool))
            case S_IFREG:
                let cloud = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                guard cloud.isUbiquitousItem != true || cloud.ubiquitousItemDownloadingStatus == .current else { throw CacheSSDError.message(L10n.text("Há conteúdo da nuvem ainda não baixado. A origem será preservada.")) }
                entry = ManifestEntry(path: rel, kind: "file", size: Int64(metadata.st_size), digest: try hash(url, cancellation: cancellation), metadata: try metadataDigest(url))
            default: throw CacheSSDError.message(L10n.text("O cache contém um arquivo especial em uso; a migração foi adiada."))
            }
            try visit(entry); count += 1
            if count % 200 == 0 { progress("Conferindo \(count) itens…") }
        }
        if failed { throw CacheSSDError.message(L10n.text("A leitura ficou incompleta por falta de acesso. Nenhum conteúdo será liberado.")) }
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
        var finished = false
        while !finished {
            try autoreleasepool {
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { finished = true; return }
                if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada.")) }
                hash.update(data: data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func copy(_ source: URL, to target: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws {
        let source = Paths.physicalURL(source), fm = FileManager.default
        guard !Paths.contains(target.resolvingSymlinksInPath(), in: source) else { throw CacheSSDError.message(L10n.text("Escolha uma pasta independente e sem links.")) }
        guard !fm.fileExists(atPath: target.path) else { throw CacheSSDError.message(L10n.text("O destino já existe. Nenhum arquivo foi sobrescrito.")) }
        var rootInfo = stat()
        guard lstat(source.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message(L10n.text("A origem está indisponível.")) }
        // Check the nearest existing parent before writing even an empty stage.
        var parent = target.deletingLastPathComponent()
        while !fm.fileExists(atPath: parent.path), parent.path != "/" { parent.deleteLastPathComponent() }
        try validateDestination(parent)
        try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directories = try VerificationStore(workspace: target.deletingLastPathComponent())
        try directories.add(ManifestEntry(path: "", kind: "directory", size: 0, digest: ""))
        var failed = false, count = 0
        guard let e = fm.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível ler a origem.")) }
        let prefix = source.path == "/" ? "/" : source.path + "/"
        try enumerate(e) { url in
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { return }
            guard url.path.hasPrefix(prefix) else { throw CacheSSDError.message(L10n.text("O caminho de cópia não pertence à origem.")) }
            let rel = String(url.path.dropFirst(prefix.count)), dest = target.appendingPathComponent(rel)
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { throw CacheSSDError.message(L10n.text("A origem mudou durante a cópia.")) }
            guard metadata.st_dev == rootInfo.st_dev else { throw CacheSSDError.message(L10n.text("A origem contém outro volume montado.")) }
            switch metadata.st_mode & S_IFMT {
            case S_IFDIR:
                try fm.createDirectory(at: dest, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try directories.add(ManifestEntry(path: rel, kind: "directory", size: 0, digest: ""))
            case S_IFLNK: try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: linkTarget(url, root: source, tool: tool))
            case S_IFREG: try copyRegular(url, to: dest, cancellation: cancellation, progress: progress)
            default: throw CacheSSDError.message(L10n.text("Arquivos especiais não são copiados."))
            }
            count += 1
            if count % 200 == 0 { progress("Copiando \(count) itens…") }
        }
        if failed { throw CacheSSDError.message(L10n.text("A cópia ficou incompleta por falta de acesso. A origem foi preservada.")) }
        try directories.forEach(deepestFirst: true) { entry, _ in
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
            let from = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
            let to = entry.path.isEmpty ? target : target.appendingPathComponent(entry.path)
            guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível preservar os metadados da pasta. A origem foi mantida.")) }
        }
    }

    private static func copyRegular(_ source: URL, to target: URL, cancellation: CancellationFlag, progress: (String) -> Void) throws {
        try validateDestination(target.deletingLastPathComponent())
        var initial = stat()
        guard lstat(source.path, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG, initial.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message(L10n.text("O arquivo não está disponível localmente.")) }
        let cloud = try source.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard cloud.isUbiquitousItem != true || cloud.ubiquitousItemDownloadingStatus == .current else { throw CacheSSDError.message(L10n.text("Baixe o arquivo no Finder antes de movê-lo.")) }
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { throw CacheSSDError.message(L10n.text("O arquivo mudou ou não permite leitura.")) }
        defer { close(input) }
        var opened = stat()
        guard fstat(input, &opened) == 0, opened.st_dev == initial.st_dev, opened.st_ino == initial.st_ino, opened.st_mode & S_IFMT == S_IFREG, opened.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message(L10n.text("O arquivo mudou durante a leitura.")) }
        guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
        let output = open(target.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível gravar a cópia. A origem foi preservada.")) }
        defer { close(output) }
        var buffer = [UInt8](repeating: 0, count: Int(min(1_048_576, max(1, opened.st_size)))), total: Int64 = 0
        while true {
            guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível ler a origem.")) }
            if count == 0 { break }
            total += Int64(count)
            guard total <= Int64(opened.st_size) else { throw CacheSSDError.message(L10n.text("A origem mudou durante a cópia.")) }
            try buffer.withUnsafeBytes { bytes in
                var offset = 0
                while offset < count {
                    guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Cópia cancelada; origem preservada.")) }
                    let written = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw CacheSSDError.message(L10n.text("Não foi possível gravar a cópia. A origem foi preservada.")) }
                    offset += written
                }
            }
            if total % 16_777_216 == 0 { progress("Copiando \(ByteText.format(total))…") }
        }
        var finished = stat()
        guard fstat(input, &finished) == 0, total == Int64(opened.st_size), finished.st_size == opened.st_size,
              finished.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec, finished.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec else { throw CacheSSDError.message(L10n.text("A origem mudou durante a cópia.")) }
        guard fcopyfile(input, output, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0, fsync(output) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível preservar os metadados da cópia. A origem foi mantida.")) }
    }

    public static func copyItem(_ source: URL, to target: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws {
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw CacheSSDError.message(L10n.text("A origem está indisponível.")) }
        if info.st_mode & S_IFMT == S_IFDIR { try copy(source, to: target, tool: tool, cancellation: cancellation, progress: progress) }
        else if info.st_mode & S_IFMT == S_IFREG { try copyRegular(source, to: target, cancellation: cancellation, progress: progress) }
        else { throw CacheSSDError.message(L10n.text("Arquivos especiais não são copiados.")) }
    }

    public static func digest(_ root: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), workspace: URL? = nil, progress: (String) -> Void = { _ in }) throws -> String {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { throw CacheSSDError.message(L10n.text("A origem está indisponível ou foi redirecionada.")) }
        var digest = SHA256()
        digest.update(data: Data(try metadataDigest(root).utf8))
        if info.st_mode & S_IFMT == S_IFDIR {
            if let workspace, Paths.contains(workspace.resolvingSymlinksInPath(), in: Paths.physicalURL(root)) { throw CacheSSDError.message(L10n.text("Escolha uma pasta independente e sem links.")) }
            let entries = try VerificationStore(workspace: workspace)
            try visitManifest(root, tool: tool, cancellation: cancellation, progress: progress) { try entries.add($0) }
            digest.update(data: Data("[".utf8))
            var first = true
            try entries.forEach { _, json in
                guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                if !first { digest.update(data: Data(",".utf8)) }; first = false
                digest.update(data: json)
            }
            digest.update(data: Data("]".utf8))
        } else if info.st_mode & S_IFMT == S_IFREG {
            let cloud = try root.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard cloud.isUbiquitousItem != true || cloud.ubiquitousItemDownloadingStatus == .current else { throw CacheSSDError.message(L10n.text("Baixe o arquivo no Finder antes de movê-lo.")) }
            digest.update(data: Data(try hash(root, cancellation: cancellation).utf8))
        } else { throw CacheSSDError.message(L10n.text("Arquivos especiais não podem receber esta operação.")) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copy-relevant metadata; access times and filesystem compression are not content.
    public static func metadataDigest(_ url: URL) throws -> String {
        try metadataDigest(url, excludingQuarantine: false)
    }
    // Provider-only comparison seam. The public digest and all historical
    // operation digests retain the exact same quarantine-inclusive bytes.
    static func metadataDigest(_ url: URL, excludingQuarantine: Bool) throws -> String {
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
                if excludingQuarantine && name == "com.apple.quarantine" { continue }
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
    static func metadataDigest(descriptor: Int32, excludingQuarantine: Bool) throws -> String {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message("Não foi possível conferir os metadados.") }
        var components = [String(info.st_mode & 0o777), "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"]
        let length = flistxattr(descriptor, nil, 0, 0)
        guard length >= 0 else { throw CacheSSDError.message("Não foi possível ler atributos do arquivo.") }
        if length > 0 {
            var names = [CChar](repeating: 0, count: length)
            guard flistxattr(descriptor, &names, length, 0) == length else { throw CacheSSDError.message("Os atributos mudaram durante a leitura.") }
            let strings = names.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }.sorted()
            for name in strings where name != "com.apple.decmpfs" && name != "com.apple.lastuseddate#PS" && (!excludingQuarantine || name != "com.apple.quarantine") {
                let count = fgetxattr(descriptor, name, nil, 0, 0, 0)
                guard count >= 0, count <= 16_777_216 else { throw CacheSSDError.message("O atributo está indisponível ou excede o limite desta versão. A origem foi preservada.") }
                var bytes = [UInt8](repeating: 0, count: max(1, count))
                guard fgetxattr(descriptor, name, &bytes, count, 0, 0) == count else { throw CacheSSDError.message("Os atributos mudaram durante a leitura.") }
                components.append(name + ":" + SHA256.hash(data: Data(bytes.prefix(count))).map { String(format: "%02x", $0) }.joined())
            }
        }
        if let acl = acl_get_fd(descriptor) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var count = ssize_t(0)
            guard let text = acl_to_text(acl, &count) else { throw CacheSSDError.message("Não foi possível conferir as permissões estendidas.") }
            components.append(String(cString: text)); acl_free(text)
        } else if errno != ENOENT && errno != ENOTSUP { throw CacheSSDError.message("Não foi possível ler as permissões estendidas.") }
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
        let parent = Paths.comparisonPath(link.deletingLastPathComponent()).split(separator: "/"), child = Paths.comparisonPath(resolved).split(separator: "/")
        var common = 0
        while common < min(parent.count, child.count), parent[common] == child[common] { common += 1 }
        return (Array(repeating: "..", count: parent.count - common) + child.dropFirst(common).map(String.init)).joined(separator: "/")
    }
}

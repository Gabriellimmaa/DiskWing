import Foundation
import CryptoKit
import Darwin

public struct ManifestEntry: Codable, Equatable {
    public let path: String
    public let kind: String
    public let size: Int64
    public let digest: String
}

public enum FileTree {
    public static func measure(_ root: URL) -> (logical: Int64, allocated: Int64, entries: Int) {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in false }) else { return (0,0,0) }
        var logical: Int64 = 0, allocated: Int64 = 0, entries = 0
        var seen = Set<String>()
        for case let url as URL in e {
            entries += 1
            var s = stat()
            guard lstat(url.path, &s) == 0 else { continue }
            if (s.st_mode & S_IFMT) == S_IFLNK { e.skipDescendants(); continue }
            if (s.st_mode & S_IFMT) == S_IFREG {
                logical += Int64(s.st_size)
                if seen.insert("\(s.st_dev):\(s.st_ino)").inserted { allocated += Int64(s.st_blocks) * 512 }
            }
        }
        return (logical, allocated, entries)
    }

    public static func manifest(_ root: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws -> [ManifestEntry] {
        let root = Paths.physicalURL(root)
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw CacheSSDError.message("A origem não é uma pasta disponível.") }
        var enumerationFailed = false
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw CacheSSDError.message("Não foi possível enumerar o cache.") }
        var entries: [ManifestEntry] = []
        for case let url as URL in e {
            if cancellation.isCancelled { throw CacheSSDError.message("Operação cancelada. A origem foi preservada.") }
            guard url.path.hasPrefix(root.path + "/") else { throw CacheSSDError.message("O caminho enumerado não pertence à origem.") }
            let rel = String(url.path.dropFirst(root.path.count + 1))
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { continue }
            var s = stat()
            guard lstat(url.path, &s) == 0 else { throw CacheSSDError.message("Um arquivo mudou durante a leitura. Tente novamente com a ferramenta fechada.") }
            switch s.st_mode & S_IFMT {
            case S_IFDIR: entries.append(ManifestEntry(path: rel, kind: "directory", size: 0, digest: ""))
            case S_IFLNK:
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                guard !target.hasPrefix("/"), Paths.contains(url.resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()) else { throw CacheSSDError.message("Este cache contém um link externo e não pode ser migrado por esta versão.") }
                entries.append(ManifestEntry(path: rel, kind: "link", size: 0, digest: target)); e.skipDescendants()
            case S_IFREG:
                let cloud = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if cloud?.isUbiquitousItem == true && cloud?.ubiquitousItemDownloadingStatus != .current { throw CacheSSDError.message("Há conteúdo da nuvem ainda não baixado. A origem será preservada.") }
                if entries.count % 200 == 0 { progress("Conferindo \(entries.count) itens…") }
                entries.append(ManifestEntry(path: rel, kind: "file", size: Int64(s.st_size), digest: try hash(url, cancellation: cancellation)))
            default: throw CacheSSDError.message("O cache contém um arquivo especial em uso; a migração foi adiada.")
            }
        }
        if enumerationFailed { throw CacheSSDError.message("A leitura ficou incompleta por falta de acesso. Nenhum conteúdo será liberado.") }
        return entries.sorted { $0.path < $1.path }
    }

    public static func hash(_ url: URL, cancellation: CancellationFlag = CancellationFlag()) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            if cancellation.isCancelled { throw CacheSSDError.message("Operação cancelada.") }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func copy(_ source: URL, to target: URL, tool: String = "", cancellation: CancellationFlag = CancellationFlag(), progress: (String) -> Void = { _ in }) throws {
        let source = Paths.physicalURL(source)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw CacheSSDError.message("O destino já existe. Nenhum arquivo foi sobrescrito.") }
        try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var enumerationFailed = false
        guard let e = fm.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw CacheSSDError.message("Não foi possível ler a origem.") }
        var count = 0
        for case let url as URL in e {
            if cancellation.isCancelled { throw CacheSSDError.message("Cópia cancelada; origem preservada.") }
            if tool == "gradle" && (url.lastPathComponent.hasSuffix(".lock") || url.lastPathComponent == "gc.properties") { continue }
            guard url.path.hasPrefix(source.path + "/") else { throw CacheSSDError.message("O caminho de cópia não pertence à origem.") }
            let rel = String(url.path.dropFirst(source.path.count + 1)), dest = target.appendingPathComponent(rel)
            var s = stat()
            guard lstat(url.path, &s) == 0 else { throw CacheSSDError.message("A origem mudou durante a cópia.") }
            if (s.st_mode & S_IFMT) == S_IFDIR { try fm.createDirectory(at: dest, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: s.st_mode & 0o777)]) }
            else { try fm.copyItem(at: url, to: dest) }
            count += 1
            if count % 200 == 0 { progress("Copiando \(count) itens…") }
        }
        if enumerationFailed { throw CacheSSDError.message("A cópia ficou incompleta por falta de acesso. A origem foi preservada.") }
    }
}

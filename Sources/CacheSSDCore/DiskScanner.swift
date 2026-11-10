import Foundation
import Darwin

public final class DiskScanner {
    public let maxEntries: Int
    public let childrenPerFolder: Int
    private let home: URL
    public init(maxEntries: Int = 200_000, childrenPerFolder: Int = 120, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.maxEntries = maxEntries; self.childrenPerFolder = childrenPerFolder; self.home = home
    }

    public func scan(_ root: URL, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        let root = Paths.physicalURL(root)
        let started = Date()
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível acessar a pasta selecionada.")) }
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else { throw CacheSSDError.message(L10n.text("Selecione uma pasta real para analisar.")) }
        let device = rootStat.st_dev
        var entries = 0, bytes: Int64 = 0
        var unreadable: [String] = [], mounts: [String] = [], largest: [ScanItem] = []
        var hardLinks = Set<String>()
        var lastProgress = Date.distantPast
        var limited = false

        func visit(_ url: URL, depth: Int) -> ScanItem? {
            if cancellation.isCancelled { return nil }
            guard entries < maxEntries, depth <= 80 else { limited = true; return nil }
            entries += 1
            if Date().timeIntervalSince(lastProgress) > 0.25 {
                lastProgress = Date(); progress(ScanProgress(entries: entries, logicalBytes: bytes, currentPath: url.path))
            }
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                if unreadable.count < 200 { unreadable.append(url.path) }
                return ScanItem(path: url.path, name: url.lastPathComponent, isDirectory: false, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: category(url), issue: "Não foi possível ler", children: [])
            }
            let type = info.st_mode & S_IFMT
            let directory = type == S_IFDIR, link = type == S_IFLNK
            if info.st_dev != device {
                if mounts.count < 100 { mounts.append(url.path) }
                return ScanItem(path: url.path, name: url.lastPathComponent, isDirectory: directory, isSymbolicLink: link, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: category(url), issue: "Outro volume; analise separadamente", children: [])
            }
            if link {
                return ScanItem(path: url.path, name: url.lastPathComponent, isDirectory: false, isSymbolicLink: true, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: category(url), issue: "Link; destino não percorrido", children: [])
            }
            if !directory {
                guard type == S_IFREG else { return nil }
                let logical = Int64(info.st_size)
                let identity = "\(info.st_dev):\(info.st_ino)"
                let duplicate = info.st_nlink > 1 && !hardLinks.insert(identity).inserted
                let allocated = duplicate ? 0 : Int64(info.st_blocks) * 512
                bytes += logical
                let dataless = info.st_flags & UInt32(SF_DATALESS) != 0
                let item = ScanItem(path: url.path, name: url.lastPathComponent, isDirectory: false, isSymbolicLink: false, logicalBytes: logical, allocatedBytes: allocated, fileCount: 1, category: category(url), issue: dataless ? "Há conteúdo da nuvem ainda não baixado. A origem será preservada." : duplicate ? "Blocos já contados em outro hard link" : nil, children: [], coverage: dataless ? .partial : .complete)
                if largest.count < 60 || logical > (largest.last?.logicalBytes ?? 0) {
                    largest.append(item); largest.sort { $0.logicalBytes > $1.logicalBytes }
                    if largest.count > 60 { largest.removeLast() }
                }
                return item
            }
            var childItems: [ScanItem] = [], total: Int64 = 0, allocated: Int64 = 0, count = 0
            var issue: String?
            var omittedChildren = false
            var incomplete = false
            var incompleteChildren = false
            do {
                let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                for child in children {
                    if cancellation.isCancelled || entries >= maxEntries { if entries >= maxEntries { limited = true }; incomplete = true; break }
                    if let item = visit(child, depth: depth + 1) {
                        if !item.isSymbolicLink && item.coverage != .complete { incompleteChildren = true }
                        total += item.logicalBytes; allocated += item.allocatedBytes; count += item.fileCount
                        childItems.append(item)
                        if childItems.count > childrenPerFolder * 2 {
                            omittedChildren = true
                            childItems.sort { $0.logicalBytes > $1.logicalBytes }
                            childItems = Array(childItems.prefix(childrenPerFolder))
                        }
                    } else if limited || cancellation.isCancelled { incomplete = true }
                }
                childItems.sort { $0.logicalBytes > $1.logicalBytes }
                if childItems.count > childrenPerFolder { childItems = Array(childItems.prefix(childrenPerFolder)); omittedChildren = true }
                if omittedChildren { issue = "Exibindo os \(childrenPerFolder) maiores itens; total inclui todos os itens lidos" }
            } catch {
                if unreadable.count < 200 { unreadable.append(url.path) }
                issue = "Sem acesso; tamanho desconhecido"
            }
            let coverage = ScanCoverage.legacy(issue: issue, isLink: false, children: childItems)
            return ScanItem(path: url.path, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: total, allocatedBytes: allocated, fileCount: count, category: category(url), issue: issue, children: childItems, coverage: (incomplete || incompleteChildren) && coverage == .complete ? .partial : coverage)
        }
        guard let item = visit(root.standardizedFileURL, depth: 0) else { throw CacheSSDError.message(L10n.text("Análise cancelada antes de iniciar.")) }
        return ScanReport(id: UUID(), root: item, startedAt: started, finishedAt: Date(), examinedEntries: entries, unreadablePaths: unreadable, skippedMounts: mounts, isCancelled: cancellation.isCancelled, reachedLimit: limited, largestFiles: largest)
    }

    func category(_ url: URL) -> ContentCategory {
        let path = url.path
        if path.contains("/Library/Caches/") || path.contains("/.npm/_cacache") || path.contains("/.gradle/caches") || path.contains("/.bun/install/cache") { return .cache }
        if path.contains("/Library/Developer") || path.contains("/Library/Android") || path.contains("/.android") || path.contains("/.gradle") || path.contains("/node_modules/") { return .developer }
        if path.hasSuffix(".app") || path.contains(".app/") || path.hasSuffix(".photoslibrary") { return .application }
        if path.contains("/Library/") || path.hasPrefix("/System/") { return .system }
        for name in ["Downloads", "Documents", "Desktop", "Movies", "Pictures", "Music"] {
            if Paths.contains(url, in: home.appendingPathComponent(name)) { return .personal }
        }
        if path.hasPrefix("/private/") { return .system }
        return .unknown
    }
}

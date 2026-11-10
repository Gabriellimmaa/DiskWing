import Foundation
import AppKit

public enum PersonalActionPolicy {
    public static func reasonPreventing(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let item = url.standardizedFileURL
        guard item == item.resolvingSymlinksInPath() else { return "Links e caminhos redirecionados ficam fora das ações automáticas." }
        let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        guard roots.contains(where: { item != $0 && Paths.contains(item, in: $0) }) else { return "Ações de arquivos estão disponíveis dentro das suas pastas pessoais. Caches e dados de aplicativos usam integrações específicas." }
        let forbidden: Set<String> = ["Library", ".git", "node_modules", ".npm", ".gradle", ".android", ".codex"]
        guard !item.pathComponents.contains(where: { forbidden.contains($0) }) else { return "Este item pertence a uma ferramenta ou a dados de aplicativo." }
        let packages: Set<String> = ["app", "photoslibrary", "photolibrary", "sparsebundle", "pvm", "utm", "vmwarevm", "framework"]
        guard !item.pathComponents.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { return "Bibliotecas e pacotes precisam de um procedimento específico de seu aplicativo." }
        if let values = try? item.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return "Baixe este arquivo no Finder antes de movê-lo. O CacheSSD não baixará arquivos da nuvem por conta própria." }
        return nil
    }
}

public final class PersonalActions {
    private let home: URL
    private let store: Store
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, store: Store = Store()) { self.home = home; self.store = store }
    public func trash(_ url: URL) throws -> OperationRecord {
        if let reason = PersonalActionPolicy.reasonPreventing(url, home: home) { throw CacheSSDError.message(reason) }
        guard try BusyInspector.inspect(paths: [url]).isEmpty else { throw CacheSSDError.message("O item está em uso. Feche o aplicativo que o utiliza.") }
        let before = Volumes.free(at: url)
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        let record = OperationRecord(title: "Item enviado à Lixeira", detail: "\(url.lastPathComponent). O espaço será liberado quando a Lixeira for esvaziada no Finder.", measuredFreeDelta: Volumes.free(at: home) - before, recoveryPath: result?.path)
        try store.append(record); return record
    }
    public func move(_ source: URL, to directory: URL, progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        if let reason = PersonalActionPolicy.reasonPreventing(source, home: home) { throw CacheSSDError.message(reason) }
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath(), !Paths.contains(directory, in: source) else { throw CacheSSDError.message("Escolha uma pasta de destino independente e sem links.") }
        let final = directory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: final.path) else { throw CacheSSDError.message("Já existe um item com esse nome no destino. Nada foi sobrescrito.") }
        guard try BusyInspector.inspect(paths: [source]).isEmpty else { throw CacheSSDError.message("O item está em uso.") }
        let before = Volumes.free(at: source)
        let folder = (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        let staging = directory.appendingPathComponent(".CacheSSD-move-\(UUID().uuidString)")
        progress("Copiando e conferindo o item…")
        let manifest = folder ? try FileTree.manifest(source) : []
        let digest = folder ? "" : try FileTree.hash(source)
        try FileManager.default.copyItem(at: source, to: staging)
        if folder {
            guard try FileTree.manifest(staging) == manifest, try FileTree.manifest(source) == manifest else { throw CacheSSDError.message("O conteúdo mudou ou não passou pela conferência. A origem foi mantida.") }
        } else {
            guard try FileTree.hash(staging) == digest, try FileTree.hash(source) == digest else { throw CacheSSDError.message("O arquivo mudou ou não passou pela conferência. A origem foi mantida.") }
        }
        guard source.standardizedFileURL == source.resolvingSymlinksInPath(), try BusyInspector.inspect(paths: [source]).isEmpty else { throw CacheSSDError.message("A origem passou a ser utilizada; ela foi preservada.") }
        try FileManager.default.moveItem(at: staging, to: final)
        // Move the original to the Trash, so the action remains recoverable without deleting personal data.
        var trashURL: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &trashURL)
        let record = OperationRecord(title: "Arquivo copiado e origem na Lixeira", detail: "Cópia conferida em \(final.path). Revise e esvazie a Lixeira no Finder para liberar o espaço da origem.", measuredFreeDelta: Volumes.free(at: home) - before, recoveryPath: final.path)
        try store.append(record); return record
    }
}

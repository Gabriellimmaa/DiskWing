import Foundation
import AppKit
import Darwin

public enum PersonalActionPolicy {
    /// Manual Trash has a wider scope than relocation. Eligibility never means
    /// that the selected data is disposable; the UI still reviews the selection.
    public static func reasonPreventingTrash(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, storeBase: URL? = nil) -> String? {
        let requestedHome = home
        let item = url.standardizedFileURL, home = home.standardizedFileURL
        // Directory hints on an absent URL differ across Foundation versions.
        // Inspect the actual supplied components, before standardization can
        // abbreviate a physical /private/var path to its /var symlink alias.
        guard url.isFileURL, requestedHome.isFileURL, trashPathIsUnredirected(url), trashPathIsUnredirected(requestedHome) else { return "Links e caminhos redirecionados ficam fora das ações automáticas." }
        guard item.path != home.path, Paths.contains(item, in: home) else { return "A exclusão manual está disponível dentro da sua pasta pessoal. Raízes e áreas do sistema são preservadas." }
        let structural = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures", "Public", "Applications", "Library", "Library/Caches", "Library/Application Support", "Library/Containers", "Library/Group Containers", "Library/Developer", "Library/Preferences", ".config"]
        guard !structural.contains(where: { item.path.caseInsensitiveCompare(home.appendingPathComponent($0).path) == .orderedSame }) else { return "Esta é uma pasta estrutural. Abra-a e selecione um item específico para revisar." }
        let storage = Paths.physicalURL(storeBase ?? home.appendingPathComponent("Library/Application Support/CacheSSD")).standardizedFileURL
        guard !trashPathsOverlap(item, storage) else { return "Os registros do DiskWing e suas pastas de recuperação são preservados." }
        let protected = [
            ".Trash", ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".codex", ".config/gcloud", ".config/gh",
            "Library/Keychains", "Library/Accounts", "Library/Safari",
            "Library/Containers/com.apple.Safari", "Library/Containers/com.apple.Passwords", "Library/Group Containers/group.com.apple.safari", "Library/Group Containers/group.com.apple.Passwords",
            "Library/Application Support/Google/Chrome", "Library/Application Support/Chromium",
            "Library/Application Support/Microsoft Edge", "Library/Application Support/BraveSoftware/Brave-Browser", "Library/Application Support/Firefox",
            "Library/Developer/CoreSimulator", "Library/Android", ".android", ".rustup", ".sdkman", ".nvm", ".pyenv", ".rbenv",
            ".bun/install/cache", ".cache/uv", ".local/share/uv", ".npm/_npx", ".gradle/jdks", ".gradle/wrapper", ".cargo/bin"
        ].map { home.appendingPathComponent($0) }
        guard !protected.contains(where: { trashPathsOverlap(item, $0) }) else { return "Esta seleção contém credenciais, perfis, SDKs ou instalações que precisam ser preservados." }
        let relative = item.pathComponents.dropFirst(home.pathComponents.count)
        let sensitive: Set<String> = [".git", ".hg", ".svn", ".netrc", ".npmrc", ".pypirc", ".git-credentials", "id_rsa", "id_ed25519", "id_ecdsa", "node_modules", ".venv", "venv", "site-packages"]
        guard !relative.contains(where: { sensitive.contains($0.lowercased()) || $0.lowercased() == ".env" || $0.lowercased().hasPrefix(".env.") }) else { return "Esta seleção contém credenciais ou dados internos de um projeto que precisam ser preservados." }
        let packages: Set<String> = ["app", "photoslibrary", "photolibrary", "sparsebundle", "pvm", "utm", "vmwarevm", "framework"]
        guard !relative.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { return "Bibliotecas e pacotes precisam de um procedimento específico." }
        var metadata = stat()
        if lstat(item.path, &metadata) == 0 {
            if let reason = trashMetadataReason(metadata) { return reason }
        } else if errno != ENOENT { return "Não foi possível examinar este item. A origem será preservada." }
        // A missing source can be assessed when validating a recovery journal.
        if let values = try? item.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
        return nil
    }

    /// Foundation may leave an absent leaf unchanged even when its parent has
    /// become a symlink. Recovery must inspect every existing path component.
    private static func trashPathIsUnredirected(_ item: URL) -> Bool {
        let components = Array(item.pathComponents.dropFirst())
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for (index, component) in components.enumerated() {
            current.appendPathComponent(component)
            var metadata = stat()
            if lstat(current.path, &metadata) != 0 { return errno == ENOENT }
            if metadata.st_mode & S_IFMT == S_IFLNK { return false }
            if index < components.count - 1 && metadata.st_mode & S_IFMT != S_IFDIR { return false }
        }
        return true
    }

    private static func trashPathsOverlap(_ lhs: URL, _ rhs: URL) -> Bool {
        // Conservatively protect aliases on the usual case-insensitive APFS
        // volume without granting extra access on case-sensitive volumes.
        let a = lhs.standardizedFileURL.path.lowercased(), b = rhs.standardizedFileURL.path.lowercased()
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    static func trashMetadataReason(_ metadata: stat) -> String? {
        if metadata.st_flags & UInt32(SF_DATALESS) != 0 { return "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
        guard [S_IFREG, S_IFDIR].contains(metadata.st_mode & S_IFMT) else { return "Links e arquivos especiais são preservados pela exclusão manual." }
        if metadata.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE) != 0 { return "Este item está protegido pelo sistema de arquivos. A origem será preservada." }
        return nil
    }

    public static func trashWarning(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let item = url.standardizedFileURL, home = home.standardizedFileURL
        let caches = home.appendingPathComponent("Library/Caches")
        if Paths.contains(item, in: caches) || CacheCatalog.all(home: home).contains(where: { Paths.contains(item, in: $0.source) }) {
            return "Um cache pode guardar informações importantes. A exclusão pode exigir novos downloads ou reconstruções e não redireciona novos arquivos para o SSD. Feche o aplicativo e revise o conteúdo."
        }
        if Paths.contains(item, in: home.appendingPathComponent("Library")) || item.pathComponents.dropFirst(home.pathComponents.count).first?.hasPrefix(".") == true {
            return "Este item pode conter configurações ou dados de aplicativo. A exclusão pode perder informações ou exigir reconfiguração. Revise o conteúdo e feche o aplicativo antes de confirmar."
        }
        return nil
    }

    public static func validateTrashTree(_ source: URL, home: URL, storeBase: URL? = nil, cancellation: CancellationFlag, maxEntries: Int = 1_000_000, progress: (String) -> Void = { _ in }) throws {
        if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
        guard maxEntries > 0 else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
        if let reason = reasonPreventingTrash(source, home: home, storeBase: storeBase) { throw CacheSSDError.message(reason) }
        var rootInfo = stat()
        guard lstat(source.path, &rootInfo) == 0 else { throw CacheSSDError.message(L10n.text("O item não está mais disponível.")) }
        if rootInfo.st_mode & S_IFMT != S_IFDIR { return }
        var failed = false
        guard let e = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
        var count = 0, finished = false
        while !finished {
            try autoreleasepool {
                for _ in 0..<256 {
                    if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                    guard let child = e.nextObject() as? URL else { finished = true; break }
                    guard count < maxEntries else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
                    if let reason = reasonPreventingTrash(child, home: home, storeBase: storeBase) { throw CacheSSDError.message(reason) }
                    var metadata = stat()
                    guard lstat(child.path, &metadata) == 0, metadata.st_dev == rootInfo.st_dev else { throw CacheSSDError.message(L10n.text("A origem contém outro volume montado ou mudou durante a inspeção. Ela foi preservada.")) }
                    count += 1
                    if count % 200 == 0 { progress("Inspecionando \(count) itens…") }
                }
            }
        }
        if failed { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
    }

    public static func reasonPreventing(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let item = url.standardizedFileURL
        guard item == item.resolvingSymlinksInPath() else { return "Links e caminhos redirecionados ficam fora das ações automáticas." }
        var metadata = stat()
        if lstat(item.path, &metadata) == 0, metadata.st_flags & UInt32(SF_DATALESS) != 0 { return "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
        let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        guard roots.contains(where: { item != $0 && Paths.contains(item, in: $0) }) else { return "Ações de arquivos estão disponíveis dentro das suas pastas pessoais. Dados de aplicativos usam integrações específicas." }
        let forbidden: Set<String> = ["Library", ".git", "node_modules", ".npm", ".gradle", ".android", ".codex"]
        guard !item.pathComponents.contains(where: { forbidden.contains($0) }) else { return "Este item pertence a uma ferramenta ou a dados de aplicativo." }
        let packages: Set<String> = ["app", "photoslibrary", "photolibrary", "sparsebundle", "pvm", "utm", "vmwarevm", "framework"]
        guard !item.pathComponents.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { return "Bibliotecas e pacotes precisam de um procedimento específico." }
        if let values = try? item.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return "Baixe este arquivo no Finder antes de movê-lo. O DiskWing não baixa conteúdo da nuvem." }
        return nil
    }
    public static func validateTree(_ source: URL, home: URL, cancellation: CancellationFlag, maxEntries: Int = 1_000_000, progress: (String) -> Void = { _ in }) throws {
        if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
        guard maxEntries > 0 else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
        if let reason = reasonPreventing(source, home: home) { throw CacheSSDError.message(reason) }
        if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true { return }
        var failed = false
        guard let e = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
        var finished = false, count = 0
        while !finished {
            try autoreleasepool {
                for _ in 0..<256 {
                    if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                    guard let child = e.nextObject() as? URL else { finished = true; break }
                    guard count < maxEntries else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
                    if let reason = reasonPreventing(child, home: home) { throw CacheSSDError.message(reason) }
                    count += 1
                    if count % 200 == 0 { progress("Inspecionando \(count) itens…") }
                }
            }
        }
        if failed { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
    }
}

public final class PersonalActions {
    private let home: URL
    private let store: Store
    private let trashHandler: (URL) throws -> URL?
    private let freeBytes: (URL) -> Int64
    private let busyCheck: BusyCheck
    private let checkpoint: (OperationJournal) throws -> Void
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, store: Store = Store(),
                freeBytes: @escaping (URL) -> Int64 = { Volumes.free(at: $0) },
                trashHandler: @escaping (URL) throws -> URL? = { url in
                    var result: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                    return result.map { $0 as URL }
                }, busyCheck: @escaping BusyCheck = { try BusyInspector.inspect(paths: $0, tool: $1) },
                checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) {
        self.home = home; self.store = store; self.freeBytes = freeBytes
        self.trashHandler = trashHandler; self.busyCheck = busyCheck; self.checkpoint = checkpoint
    }
    public func trash(_ source: URL, expectedIdentity: FileIdentity? = nil, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        if let expectedIdentity, try FileIdentity(source) != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
        try PersonalActionPolicy.validateTrashTree(source, home: home, storeBase: store.base, cancellation: cancellation, progress: progress)
        guard try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("O item está em uso.")) }
        let operation = try OperationContext(store: store, kind: "trash", source: source, checkpoint: checkpoint)
        do {
            if let expectedIdentity, operation.journal.sourceIdentity != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
            try operation.advance(.verifying)
            progress("Conferindo a origem…")
            let digest = try FileTree.digest(source, cancellation: cancellation, workspace: store.base, progress: progress)
            operation.journal.sourceDigest = digest
            try operation.advance(.trashing)
            // Process inspection can be slow; source checks must follow it.
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem mudou ou a operação foi cancelada.")) }
            try operation.assertSourceIdentity()
            try PersonalActionPolicy.validateTrashTree(source, home: home, storeBase: store.base, cancellation: cancellation, progress: progress)
            guard !cancellation.isCancelled, try FileTree.digest(source, cancellation: cancellation, workspace: store.base, progress: progress) == digest,
                  !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("A origem mudou ou a operação foi cancelada.")) }
            if let reason = PersonalActionPolicy.reasonPreventingTrash(source, home: home, storeBase: store.base) { throw CacheSSDError.message(reason) }
            try operation.assertSourceIdentity()
            let result = try trashHandler(source)
            operation.journal.trashPath = result?.path
            try operation.advance(.published)
            let record = OperationRecord(title: "Item enviado à Lixeira", detail: "\(source.lastPathComponent). O espaço só será liberado quando você esvaziar a Lixeira no Finder.", recoveryPath: result?.path)
            try store.append(record)
            try operation.advance(.completed)
            return record
        } catch { operation.recordFailure(error, cancellation: cancellation); throw error }
    }
    public func move(_ source: URL, to directory: URL, expectedIdentity: FileIdentity? = nil, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        if let expectedIdentity, try FileIdentity(source) != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
        try PersonalActionPolicy.validateTree(source, home: home, cancellation: cancellation, progress: progress)
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath(), !Paths.contains(directory, in: source) else { throw CacheSSDError.message(L10n.text("Escolha uma pasta independente e sem links.")) }
        try FileTree.validateDestination(directory)
        let final = directory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: final.path) else { throw CacheSSDError.message(L10n.text("Já existe um item com esse nome. Nada foi sobrescrito.")) }
        guard try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("O item está em uso.")) }
        let size = FileTree.measure(source, cancellation: cancellation, progress: progress)
        guard size.isComplete else { throw CacheSSDError.message(L10n.text("A leitura da origem está incompleta.")) }
        guard freeBytes(directory) > max(size.logical, size.allocated) + 536_870_912 else { throw CacheSSDError.message(L10n.text("O destino não tem espaço confirmado para a cópia e a margem de segurança.")) }
        let operation = try OperationContext(store: store, kind: "personalMove", source: source, destination: final, checkpoint: checkpoint)
        let staging = directory.appendingPathComponent(".CacheSSD-move-\(operation.journal.id.uuidString)")
        operation.journal.staging = staging.path
        do {
            if let expectedIdentity, operation.journal.sourceIdentity != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
            try operation.advance(.verifying)
            let digest = try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress)
            operation.journal.sourceDigest = digest
            try operation.advance(.copying)
            try FileTree.copyItem(source, to: staging, cancellation: cancellation, progress: progress)
            guard try FileTree.digest(staging, cancellation: cancellation, workspace: directory, progress: progress) == digest,
                  try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest else { throw CacheSSDError.message(L10n.text("A cópia ou os metadados mudaram; origem preservada.")) }
            operation.journal.destinationDigest = digest
            try operation.advance(.copyVerified)
            try operation.assertSourceIdentity()
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem passou a ser utilizada ou a cópia foi cancelada.")) }
            try operation.advance(.publishing)
            guard !FileManager.default.fileExists(atPath: final.path) else { throw CacheSSDError.message(L10n.text("O destino passou a existir; nada foi sobrescrito.")) }
            try FileManager.default.moveItem(at: staging, to: final)
            try operation.advance(.published)
            try operation.assertSourceIdentity()
            guard try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest else { throw CacheSSDError.message(L10n.text("A origem mudou após a cópia; ambas foram preservadas.")) }
            try operation.advance(.trashing)
            // Process inspection can be slow; source checks must follow it.
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem passou a ser utilizada ou a cópia foi cancelada.")) }
            try operation.assertSourceIdentity()
            guard !cancellation.isCancelled, try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest,
                  !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("A origem mudou após a cópia; ambas foram preservadas.")) }
            operation.journal.trashPath = try trashHandler(source)?.path
            try operation.advance(.completed, detail: "Cópia e metadados conferidos; origem na Lixeira")
            let record = OperationRecord(title: "Arquivo copiado e origem na Lixeira", detail: "Cópia conferida em \(final.path). Revise a Lixeira no Finder antes de liberar o espaço da origem.", recoveryPath: final.path)
            try store.append(record); return record
        } catch { operation.recordFailure(error, cancellation: cancellation); throw error }
    }
}

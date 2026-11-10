import Foundation
import Darwin

public struct MigrationJournal: Codable, Identifiable {
    public let id: UUID
    public let toolID: String
    public let source: String
    public let volumeUUID: String
    public var destination: String
    public var state: String
    public var detail: String
    public let startedAt: Date
    public var localQuarantine: String? = nil
}

public final class MigrationEngine {
    public let store: Store
    private let home: URL
    private let volumeProvider: (String) -> VolumeInfo?
    private let verifyNative: Bool
    public init(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser, volumeProvider: @escaping (String) -> VolumeInfo? = { Volumes.find(uuid: $0) }, verifyNative: Bool = true) {
        self.store = store; self.home = home; self.volumeProvider = volumeProvider; self.verifyNative = verifyNative
    }

    public func migrate(toolID: String, removeLocal: Bool, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        guard let tool = CacheCatalog.find(toolID, home: home) else { throw CacheSSDError.message("Ferramenta não reconhecida.") }
        try FileManager.default.createDirectory(at: store.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockFD = open(store.base.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw CacheSSDError.message("Não foi possível registrar a operação.") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw CacheSSDError.message("Outra migração está em andamento.") }
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        var settings = store.settings()
        guard let uuid = settings.selectedVolumeUUID, let volume = volumeProvider(uuid), volume.uuid.caseInsensitiveCompare(uuid) == .orderedSame, volume.isWritable, !volume.isInternal else { throw CacheSSDError.message("Conecte o SSD selecionado e confirme que ele permite gravação.") }
        guard tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath(), FileManager.default.fileExists(atPath: tool.source.path) else { throw CacheSSDError.message("O cache local está ausente ou usa um link personalizado. Ele não será alterado.") }
        let busy = try BusyInspector.inspect(paths: [tool.source], tool: tool.id)
        guard busy.isEmpty else { throw CacheSSDError.message("Encerre antes: " + busy.map { "\($0.name) (\($0.pid))" }.joined(separator: ", ")) }
        let measurement = FileTree.measure(tool.source)
        guard measurement.logical > 0 else { throw CacheSSDError.message("O cache local está vazio.") }
        guard volume.freeBytes > max(measurement.logical, measurement.allocated) + 536_870_912 else { throw CacheSSDError.message("O SSD não tem espaço suficiente para a cópia e a margem de segurança.") }
        guard Paths.safeComponent(settings.installationID) else { throw CacheSSDError.message("O registro da instalação é inválido.") }
        let operationID = UUID()
        let relativeParent = "MacCaches/CacheSSD/\(settings.installationID)/\(tool.id)"
        let parent = URL(fileURLWithPath: volume.path).appendingPathComponent(relativeParent)
        guard parent.standardizedFileURL == parent.resolvingSymlinksInPath() else { throw CacheSSDError.message("O destino contém um link personalizado.") }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(".partial-\(operationID.uuidString)")
        let final = parent.appendingPathComponent(operationID.uuidString)
        let data = staging.appendingPathComponent("data")
        var journal = MigrationJournal(id: operationID, toolID: tool.id, source: tool.source.path, volumeUUID: volume.uuid, destination: staging.path, state: "preparing", detail: "Origem preservada", startedAt: Date())
        let journalName = "migration-\(operationID.uuidString).json"
        func saveJournal() throws { try store.write(journal, name: journalName) }
        func validateVolume() throws {
            guard let current = volumeProvider(volume.uuid), current.path == volume.path, current.isWritable else { throw CacheSSDError.message("O SSD ficou indisponível. A migração foi interrompida.") }
        }
        let beforeFree = Volumes.free(at: home)
        try saveJournal()
        do {
            progress("Conferindo a origem…")
            let original = try FileTree.manifest(tool.source, tool: tool.id, cancellation: cancellation, progress: progress)
            try validateVolume()
            journal.state = "copying"; try saveJournal()
            try FileTree.copy(tool.source, to: tool.payload(at: data), tool: tool.id, cancellation: cancellation, progress: progress)
            let copied = try FileTree.manifest(tool.payload(at: data), tool: tool.id, cancellation: cancellation, progress: progress)
            guard original == copied else { throw CacheSSDError.message("A cópia não corresponde à origem. Nenhum arquivo local foi removido.") }
            let current = try FileTree.manifest(tool.source, tool: tool.id, cancellation: cancellation, progress: progress)
            guard current == original else { throw CacheSSDError.message("O cache mudou durante a cópia. Feche a ferramenta e tente novamente.") }
            try validateVolume()
            journal.state = "verified"; try saveJournal()
            if tool.id == "gradle" { try prepareGradleHome(data) }
            if verifyNative { progress("Verificando com \(tool.name)…"); try nativeValidation(tool, root: data) }
            if cancellation.isCancelled { throw CacheSSDError.message("Operação cancelada; origem preservada.") }
            try validateVolume()
            try FileManager.default.moveItem(at: staging, to: final)
            let relative = relativeParent + "/\(operationID.uuidString)/data"
            settings.locations[tool.id] = CacheLocation(toolID: tool.id, volumeUUID: volume.uuid, relativePath: relative, migratedAt: Date(), logicalBytes: measurement.logical)
            settings.useExternal = true
            try store.save(settings)
            journal.destination = final.path; journal.state = "activated"; try saveJournal()
            var originRemoved = false
            if removeLocal && tool.canReleaseLocal {
                try validateVolume()
                let stillBusy = try BusyInspector.inspect(paths: [tool.source], tool: tool.id)
                if stillBusy.isEmpty {
                    let latest = try FileTree.manifest(tool.source, tool: tool.id, cancellation: cancellation)
                    guard latest == original, tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath() else { throw CacheSSDError.message("A origem mudou após a verificação; ela foi mantida.") }
                    // Rename first, then recheck identity. The private copy on the SSD remains available.
                    let quarantine = tool.source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-\(operationID.uuidString)")
                    journal.localQuarantine = quarantine.path; journal.state = "releasing"; try saveJournal()
                    try FileManager.default.moveItem(at: tool.source, to: quarantine)
                    do {
                        let finalManifest = try FileTree.manifest(quarantine, tool: tool.id)
                        guard finalManifest == original else { throw CacheSSDError.message("A origem mudou antes da liberação.") }
                        try FileManager.default.removeItem(at: quarantine)
                        try FileManager.default.createDirectory(at: tool.source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        originRemoved = true
                    } catch {
                        if !FileManager.default.fileExists(atPath: tool.source.path) { try? FileManager.default.moveItem(at: quarantine, to: tool.source) }
                        throw error
                    }
                }
            }
            journal.state = "completed"
            journal.detail = originRemoved ? "Cópia conferida; origem liberada" : "Cópia conferida; origem local mantida"
            try saveJournal()
            let record = OperationRecord(title: "\(tool.name) migrado", detail: journal.detail, measuredFreeDelta: Volumes.free(at: home) - beforeFree, recoveryPath: final.path)
            try store.append(record)
            return record
        } catch {
            journal.state = "interrupted"; journal.detail = error.localizedDescription; try? saveJournal()
            try? store.append(OperationRecord(title: "Migração de \(tool.name) interrompida", detail: error.localizedDescription, recoveryPath: FileManager.default.fileExists(atPath: final.path) ? final.path : staging.path))
            throw error
        }
    }

    private func prepareGradleHome(_ root: URL) throws {
        let local = home.appendingPathComponent(".gradle")
        for name in ["wrapper", "jdks", "native", "init.d", "gradle.properties"] {
            let source = local.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(name), withDestinationURL: source)
            }
        }
    }

    private func nativeValidation(_ tool: CacheDescriptor, root: URL) throws {
        var command: URL?, arguments: [String] = []
        switch tool.id {
        case "npm": command = ToolLocator.locate("npm"); arguments = ["cache", "verify"]
        case "bun": command = ToolLocator.locate("bun"); arguments = ["pm", "cache"]
        case "pip": command = ToolLocator.locate("python3"); arguments = ["-m", "pip", "cache", "info"]
        case "cocoapods": command = ToolLocator.locate("pod"); arguments = ["cache", "list", "--short"]
        case "uv": command = ToolLocator.locate("uv"); arguments = ["cache", "dir"]
        case "homebrew": command = ToolLocator.locate("brew"); arguments = ["--cache"]
        case "gradle":
            let distributions = home.appendingPathComponent(".gradle/wrapper/dists")
            if let e = FileManager.default.enumerator(at: distributions, includingPropertiesForKeys: nil) {
                for case let url as URL in e where url.lastPathComponent == "gradle" && url.deletingLastPathComponent().lastPathComponent == "bin" {
                    if FileManager.default.isExecutableFile(atPath: url.path) { command = url; break }
                }
            }
            arguments = ["--version", "--no-daemon"]
        default: break
        }
        guard let command else { throw CacheSSDError.message("\(tool.name) não foi localizado para validar a migração.") }
        var env = ToolLocator.environment(adding: [tool.environmentKey: root.path])
        // Ruby and Node shims must use the runtime installed beside the selected executable.
        env["PATH"] = command.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        let validation = store.base.appendingPathComponent("validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: validation, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: validation) }
        // Bun's package-manager commands require a project, even when only querying the cache.
        try Data("{\"name\":\"cachessd-validation\",\"version\":\"0.0.0\",\"private\":true}".utf8).write(to: validation.appendingPathComponent("package.json"))
        let result = try CommandRunner.run(command, arguments, environment: env, timeout: 120, directory: validation)
        guard result.status == 0 else { throw CacheSSDError.message("A validação de \(tool.name) falhou. A origem foi preservada; código \(result.status).") }
    }

    public func restore(toolID: String, progress: @escaping (String) -> Void = { _ in }) throws {
        guard let tool = CacheCatalog.find(toolID, home: home) else { throw CacheSSDError.message("Ferramenta desconhecida.") }
        var settings = store.settings()
        guard let location = settings.locations[toolID], let volume = volumeProvider(location.volumeUUID) else { throw CacheSSDError.message("Conecte o SSD para restaurar a cópia. O cache local também pode ser recriado normalmente pela ferramenta.") }
        guard location.relativePath.split(separator: "/").allSatisfy({ Paths.safeComponent(String($0)) }) else { throw CacheSSDError.message("Caminho de recuperação inválido.") }
        let root = URL(fileURLWithPath: volume.path).appendingPathComponent(location.relativePath)
        let source = tool.payload(at: root)
        guard root.standardizedFileURL == root.resolvingSymlinksInPath() else { throw CacheSSDError.message("O caminho da cópia foi alterado.") }
        guard try BusyInspector.inspect(paths: [source, tool.source], tool: toolID).isEmpty else { throw CacheSSDError.message("Encerre a ferramenta antes da restauração.") }
        guard FileTree.measure(tool.source).logical == 0 else { throw CacheSSDError.message("Já existe cache local. Use somente o Mac para preservá-lo; ele não será sobrescrito.") }
        guard Volumes.free(at: home) > FileTree.measure(source).logical + 536_870_912 else { throw CacheSSDError.message("Não há espaço suficiente no Mac para restaurar esta cópia.") }
        let temp = tool.source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-restore-\(UUID().uuidString)")
        let original = try FileTree.manifest(source, tool: toolID, progress: progress)
        try FileTree.copy(source, to: temp, tool: toolID, progress: progress)
        guard try FileTree.manifest(temp, tool: toolID) == original else { throw CacheSSDError.message("A restauração não passou pela verificação. A cópia no SSD está preservada.") }
        if FileManager.default.fileExists(atPath: tool.source.path) {
            guard (try FileManager.default.contentsOfDirectory(atPath: tool.source.path)).isEmpty else { throw CacheSSDError.message("O cache local foi utilizado durante a restauração; a troca foi adiada.") }
            try FileManager.default.removeItem(at: tool.source)
        }
        try FileManager.default.moveItem(at: temp, to: tool.source)
        settings.locations.removeValue(forKey: toolID); try store.save(settings)
        try store.append(OperationRecord(title: "\(tool.name) restaurado", detail: "Cache novamente no Mac. A cópia do SSD foi preservada.", recoveryPath: root.path))
    }
}

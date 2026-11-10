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
    private let busyCheck: BusyCheck
    private let checkpoint: (OperationJournal) throws -> Void
    private let adapterInspector: (CacheDescriptor) -> AdapterStatus
    private let configurationCheckpoint: (ConfigurationChange) throws -> Void
    private let nativeExecutableOverrides: [String: URL]
    public init(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser, volumeProvider: @escaping (String) -> VolumeInfo? = { Volumes.find(uuid: $0) }, verifyNative: Bool = true,
                busyCheck: @escaping BusyCheck = { try BusyInspector.inspect(paths: $0, tool: $1) },
                checkpoint: @escaping (OperationJournal) throws -> Void = { _ in },
                adapterInspector: ((CacheDescriptor) -> AdapterStatus)? = nil,
                configurationCheckpoint: @escaping (ConfigurationChange) throws -> Void = { _ in },
                nativeExecutableOverrides: [String: URL] = [:]) {
        self.store = store; self.home = home; self.volumeProvider = volumeProvider; self.verifyNative = verifyNative; self.checkpoint = checkpoint
        self.busyCheck = busyCheck
        self.adapterInspector = adapterInspector ?? { CacheAdapters.inspect($0, home: home, directory: home) }
        self.configurationCheckpoint = configurationCheckpoint
        self.nativeExecutableOverrides = nativeExecutableOverrides
    }

    public func migrate(toolID: String, removeLocal: Bool, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        guard let tool = CacheCatalog.find(toolID, home: home) else { throw CacheSSDError.message(L10n.text("Ferramenta não reconhecida.")) }
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        if verifyNative && removeLocal {
            guard adapterInspector(tool).canReleaseSource else { throw CacheSSDError.message(L10n.text("A versão ou configuração desta ferramenta ainda não permite liberar a origem. Copie mantendo o cache local.")) }
        }
        if verifyNative && ["yarn", "go", "ccache"].contains(tool.id), adapterInspector(tool).state != "native-available" { throw CacheSSDError.message(L10n.text("A ferramenta ou sua configuração não permite este direcionamento. A origem foi preservada.")) }
        var settings = store.settings()
        guard let uuid = settings.selectedVolumeUUID, let volume = volumeProvider(uuid), volume.uuid.caseInsensitiveCompare(uuid) == .orderedSame, volume.isWritable, !volume.isInternal else { throw CacheSSDError.message(L10n.text("Conecte o SSD selecionado e confirme que ele permite gravação.")) }
        try FileTree.validateDestination(URL(fileURLWithPath: volume.path))
        guard tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath(), FileManager.default.fileExists(atPath: tool.source.path) else { throw CacheSSDError.message(L10n.text("O cache local está ausente ou usa um link personalizado. Ele não será alterado.")) }
        let busy = try busyCheck([tool.source], tool.id)
        guard busy.isEmpty else { throw CacheSSDError.message(L10n.text("Encerre antes: ") + busy.map { "\($0.name) (\($0.pid))" }.joined(separator: ", ")) }
        let measurement = FileTree.measure(tool.source, cancellation: cancellation, progress: progress)
        guard measurement.isComplete else { throw CacheSSDError.message(L10n.text("A medição ficou incompleta. A origem será preservada.")) }
        guard measurement.logical > 0 else { throw CacheSSDError.message(L10n.text("O cache local está vazio.")) }
        guard volume.freeBytes > max(measurement.logical, measurement.allocated) + 536_870_912 else { throw CacheSSDError.message(L10n.text("O SSD não tem espaço suficiente para a cópia e a margem de segurança.")) }
        guard Paths.safeComponent(settings.installationID) else { throw CacheSSDError.message(L10n.text("O registro da instalação é inválido.")) }
        let operationID = UUID()
        let safety = try OperationContext(store: store, kind: "migration", source: tool.source, toolID: tool.id, id: operationID, checkpoint: checkpoint)
        let relativeParent = "MacCaches/CacheSSD/\(settings.installationID)/\(tool.id)"
        let parent = URL(fileURLWithPath: volume.path).appendingPathComponent(relativeParent)
        guard parent.standardizedFileURL == parent.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(".partial-\(operationID.uuidString)")
        let final = parent.appendingPathComponent(operationID.uuidString)
        let data = staging.appendingPathComponent("data")
        safety.journal.staging = staging.path
        safety.journal.destination = tool.payload(at: final.appendingPathComponent("data")).path
        var journal = MigrationJournal(id: operationID, toolID: tool.id, source: tool.source.path, volumeUUID: volume.uuid, destination: staging.path, state: "preparing", detail: "Origem preservada", startedAt: Date())
        let journalName = "migration-\(operationID.uuidString).json"
        func saveJournal() throws { try store.write(journal, name: journalName) }
        func validateVolume() throws {
            guard let current = volumeProvider(volume.uuid), current.path == volume.path, current.isWritable else { throw CacheSSDError.message(L10n.text("O SSD ficou indisponível. A migração foi interrompida.")) }
        }
        let beforeFree = Volumes.free(at: home)
        try saveJournal()
        do {
            try safety.advance(.verifying)
            progress("Conferindo a origem…")
            let original = try FileTree.digest(tool.source, tool: tool.id, cancellation: cancellation, workspace: parent, progress: progress)
            safety.journal.sourceDigest = original
            try validateVolume()
            journal.state = "copying"; try saveJournal(); try safety.advance(.copying)
            try FileTree.copy(tool.source, to: tool.payload(at: data), tool: tool.id, cancellation: cancellation, progress: progress)
            let copied = try FileTree.digest(tool.payload(at: data), tool: tool.id, cancellation: cancellation, workspace: parent, progress: progress)
            guard original == copied else { throw CacheSSDError.message(L10n.text("A cópia não corresponde à origem. Nenhum arquivo local foi removido.")) }
            let current = try FileTree.digest(tool.source, tool: tool.id, cancellation: cancellation, workspace: parent, progress: progress)
            guard current == original else { throw CacheSSDError.message(L10n.text("O cache mudou durante a cópia. Feche a ferramenta e tente novamente.")) }
            try validateVolume()
            journal.state = "verified"; try saveJournal(); try safety.advance(.copyVerified)
            if tool.id == "gradle" { try prepareGradleHome(data) }
            if verifyNative { progress("Verificando com \(tool.name)…"); try nativeValidation(tool, root: data) }
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
            try validateVolume()
            safety.journal.destinationDigest = try FileTree.digest(tool.payload(at: data), tool: tool.id, cancellation: cancellation, workspace: parent, progress: progress)
            try safety.advance(.publishing)
            try FileManager.default.moveItem(at: staging, to: final)
            try safety.advance(.published)
            let relative = relativeParent + "/\(operationID.uuidString)/data"
            settings.locations[tool.id] = CacheLocation(toolID: tool.id, volumeUUID: volume.uuid, relativePath: relative, migratedAt: Date(), logicalBytes: measurement.logical)
            settings.useExternal = true
            try store.save(settings)
            journal.destination = final.path; journal.state = "activated"; try saveJournal()
            var originRemoved = false
            if removeLocal && tool.canReleaseLocal {
                try validateVolume()
                let stillBusy = try busyCheck([tool.source], tool.id)
                if stillBusy.isEmpty {
                    let latest = try FileTree.digest(tool.source, tool: tool.id, cancellation: cancellation, workspace: parent, progress: progress)
                    guard latest == original, tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("A origem mudou após a verificação; ela foi mantida.")) }
                    // Rename first, then recheck identity. The private copy on the SSD remains available.
                    try safety.assertSourceIdentity()
                    let quarantine = tool.source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-\(operationID.uuidString)")
                    safety.journal.quarantine = quarantine.path
                    try safety.advance(.releasing)
                    journal.localQuarantine = quarantine.path; journal.state = "releasing"; try saveJournal()
                    try FileManager.default.moveItem(at: tool.source, to: quarantine)
                    do {
                        let finalManifest = try FileTree.digest(quarantine, tool: tool.id, workspace: parent, progress: progress)
                        guard finalManifest == original else { throw CacheSSDError.message(L10n.text("A origem mudou antes da liberação.")) }
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
            try safety.advance(.completed, detail: journal.detail)
            return record
        } catch {
            safety.recordFailure(error, cancellation: cancellation)
            journal.state = "interrupted"; journal.detail = error.localizedDescription; try? saveJournal()
            try? store.append(OperationRecord(title: "Migração de \(tool.name) interrompida", detail: error.localizedDescription, recoveryPath: FileManager.default.fileExists(atPath: final.path) ? final.path : staging.path))
            throw error
        }
    }

    /// Opt-in routing for future commands, without requiring or creating a local cache.
    /// An interrupted settings change remains a pending configuration review; no source is removed.
    public func prepareFutureCache(toolID: String, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard let tool = CacheCatalog.find(toolID, home: home) else { throw CacheSSDError.message(L10n.text("Ferramenta não reconhecida.")) }
        guard store.pendingConfigurationRecords().isEmpty else { throw CacheSSDError.message(L10n.text("Há uma configuração interrompida que precisa de revisão antes de continuar.")) }
        let status = adapterInspector(tool)
        guard status.state == "native-available" else { throw CacheSSDError.message(L10n.text("A ferramenta ou sua configuração não permite este direcionamento. A origem foi preservada.")) }
        let settingsURL = store.base.appendingPathComponent("settings.json")
        func readCurrentSettings() throws -> String {
            guard settingsURL.standardizedFileURL == settingsURL.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O registro de configuração foi redirecionado e será preservado.")) }
            let descriptor = open(settingsURL.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw CacheSSDError.message(L10n.text("O registro de configuração está indisponível e será preservado.")) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_flags & UInt32(SF_DATALESS) == 0, metadata.st_size <= 4_194_304,
                  let data = try file.read(upToCount: 4_194_305), data.count <= 4_194_304,
                  data.count == metadata.st_size, let text = String(data: data, encoding: .utf8) else { throw CacheSSDError.message(L10n.text("O registro de configuração está indisponível e será preservado.")) }
            var after = stat()
            guard fstat(descriptor, &after) == 0, after.st_dev == metadata.st_dev, after.st_ino == metadata.st_ino,
                  after.st_size == metadata.st_size, after.st_mtimespec.tv_sec == metadata.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == metadata.st_mtimespec.tv_nsec else { throw CacheSSDError.message(L10n.text("A configuração mudou durante a revisão. Ela foi preservada; tente novamente.")) }
            return text
        }
        let before = try readCurrentSettings()
        let settingsIdentity = try FileIdentity(settingsURL)
        var settings = try store.read(AppSettings.self, name: "settings.json")
        guard settings.locations[tool.id] == nil else { throw CacheSSDError.message(L10n.text("Esta ferramenta já tem um destino configurado. Revise a configuração existente.")) }
        guard let uuid = settings.selectedVolumeUUID, let volume = volumeProvider(uuid), volume.uuid.caseInsensitiveCompare(uuid) == .orderedSame,
              volume.isWritable, !volume.isInternal else { throw CacheSSDError.message(L10n.text("Conecte o SSD selecionado e confirme que ele permite gravação.")) }
        let volumeURL = URL(fileURLWithPath: volume.path)
        guard volumeURL.standardizedFileURL == volumeURL.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
        try FileTree.validateDestination(volumeURL)
        let volumeIdentity = try FileIdentity(volumeURL)
        guard volume.freeBytes > 536_870_912, Volumes.free(at: volumeURL) > 536_870_912 else { throw CacheSSDError.message(L10n.text("O SSD não tem espaço suficiente para a cópia e a margem de segurança.")) }
        guard Paths.safeComponent(settings.installationID) else { throw CacheSSDError.message(L10n.text("O registro da instalação é inválido.")) }
        func validateSource() throws {
            guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
            guard tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O cache local está ausente ou usa um link personalizado. Ele não será alterado.")) }
            let measurement = FileTree.measure(tool.source, cancellation: cancellation, progress: progress)
            guard measurement.missing || measurement.isComplete && measurement.logical == 0 else { throw CacheSSDError.message(L10n.text("O cache local contém dados. Use a migração para revisar a cópia existente.")) }
            guard try busyCheck([tool.source], tool.id).isEmpty else { throw CacheSSDError.message(L10n.text("Encerre a ferramenta antes de configurar o cache.")) }
        }
        func validateVolume() throws {
            guard let current = volumeProvider(uuid), current.uuid.caseInsensitiveCompare(uuid) == .orderedSame, current.path == volume.path,
                  current.isWritable, !current.isInternal else { throw CacheSSDError.message(L10n.text("O SSD ficou indisponível. A migração foi interrompida.")) }
            let identity = try FileIdentity(volumeURL)
            guard identity.device == volumeIdentity.device, identity.inode == volumeIdentity.inode else { throw CacheSSDError.message(L10n.text("O SSD ficou indisponível. A migração foi interrompida.")) }
        }
        try validateSource()
        let operationID = UUID()
        let relative = "MacCaches/CacheSSD/\(settings.installationID)/\(tool.id)/\(operationID.uuidString)/data"
        let destination = volumeURL.appendingPathComponent(relative)
        guard destination.standardizedFileURL == destination.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
        settings.locations[tool.id] = CacheLocation(toolID: tool.id, volumeUUID: uuid, relativePath: relative, migratedAt: Date(), logicalBytes: 0)
        settings.useExternal = true
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let after = String(decoding: try encoder.encode(settings), as: UTF8.self)
        let changeName = "configuration-\(operationID.uuidString).json"
        var change = ConfigurationChange(source: settingsURL.path, before: before, after: after)
        try store.writeDurably(change, name: changeName)
        try configurationCheckpoint(change)
        try validateVolume(); try validateSource()
        progress("Preparando destino para novos caches…")
        // Create relative to held directory descriptors. A replaced ancestor must
        // never redirect even the first mkdir into an unrelated user directory.
        try Self.createCacheDirectories(relative: relative + (tool.destinationChild.isEmpty ? "" : "/" + tool.destinationChild), volumeURL: volumeURL, volumeIdentity: volumeIdentity)
        guard destination.standardizedFileURL == destination.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
        if tool.id == "gradle" { try prepareGradleHome(destination) }
        if verifyNative { try nativeValidation(tool, root: destination) }
        try validateVolume(); try validateSource()
        guard try FileIdentity(settingsURL) == settingsIdentity, try readCurrentSettings() == before else { throw CacheSSDError.message(L10n.text("A configuração mudou durante a revisão. Ela foi preservada; tente novamente.")) }
        try store.save(settings)
        guard try readCurrentSettings() == after else { throw CacheSSDError.message(L10n.text("A configuração mudou durante a revisão. Ela foi preservada; tente novamente.")) }
        let persisted = open(settingsURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard persisted >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível confirmar o registro da operação.")) }
        defer { close(persisted) }
        guard fsync(persisted) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível persistir o registro da operação.")) }
        let directory = open(store.base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw CacheSSDError.message(L10n.text("O diretório de registros está indisponível.")) }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível persistir a pasta de registros.")) }
        let record = OperationRecord(title: "Destino para novos caches de \(tool.name) preparado", detail: "Nenhum cache local foi movido ou removido. Novas execuções pela integração podem usar o SSD; sem ele, usam o Mac.", recoveryPath: destination.path)
        try store.append(record)
        change.state = "completed"; try store.writeDurably(change, name: changeName)
        try configurationCheckpoint(change)
        return record
    }

    private static func createCacheDirectories(relative: String, volumeURL: URL, volumeIdentity: FileIdentity) throws {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy(Paths.safeComponent) else { throw CacheSSDError.message(L10n.text("Caminho de recuperação inválido.")) }
        var descriptor = open(volumeURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, Int64(metadata.st_dev) == volumeIdentity.device, UInt64(metadata.st_ino) == volumeIdentity.inode else { throw CacheSSDError.message(L10n.text("O SSD ficou indisponível. A migração foi interrompida.")) }
        for component in components {
            guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw CacheSSDError.message(L10n.text("Não foi possível preparar a pasta no SSD.")) }
            let child = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw CacheSSDError.message(L10n.text("O destino contém um link personalizado.")) }
            close(descriptor); descriptor = child
            guard fstat(descriptor, &metadata) == 0, Int64(metadata.st_dev) == volumeIdentity.device else { throw CacheSSDError.message(L10n.text("O destino contém outro volume e foi preservado.")) }
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
        case "npm":
            command = ToolLocator.locate("npm")
            // npm config get rejects UUID-containing values as protected. A script
            // owned by this validation reports npm's effective environment instead.
            // This never verifies/cleans the cache or executes project lifecycle hooks.
            arguments = ["run-script", "--silent", "--ignore-scripts", "--offline", "--audit=false", "--fund=false", "--update-notifier=false", "--workspaces=false", "--script-shell=/bin/sh", "diskwing-cache-path"]
        case "bun": command = ToolLocator.locate("bun"); arguments = ["pm", "cache"]
        case "pip": command = ToolLocator.locate("python3"); arguments = ["-m", "pip", "cache", "info"]
        case "cocoapods": command = ToolLocator.locate("pod"); arguments = ["cache", "list", "--short"]
        case "uv": command = ToolLocator.locate("uv"); arguments = ["cache", "dir"]
        case "homebrew": command = ToolLocator.locate("brew"); arguments = ["--cache"]
        case "yarn": command = ToolLocator.locate("yarn", home: home); arguments = ["--version"]
        case "go": command = ToolLocator.locate("go", home: home); arguments = ["env", "GOCACHE"]
        case "ccache": command = ToolLocator.locate("ccache", home: home); arguments = ["--get-config", "cache_dir"]
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
        // Explicit callers can supply a launcher for an already installed runtime.
        // Normal application/CLI construction never supplies an override.
        if let executable = nativeExecutableOverrides[tool.id] {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CacheSSDError.message(L10n.text("\(tool.name) não foi localizado para validar a migração.")) }
            command = executable
        }
        guard let command else { throw CacheSSDError.message(L10n.text("\(tool.name) não foi localizado para validar a migração.")) }
        var env = ToolLocator.environment(adding: ["HOME": home.path, tool.environmentKey: root.path])
        if tool.id == "go" { env["GOTOOLCHAIN"] = "local" }
        // Ruby and Node shims must use the runtime installed beside the selected executable.
        env["PATH"] = command.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        let validation = store.base.appendingPathComponent("validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: validation, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: validation) }
        // Only application-owned generated files are executable here. No package
        // is installed, and no user project or its lifecycle hooks are evaluated.
        var package: [String: Any] = ["name": "cachessd-validation", "version": "0.0.0", "private": true]
        if tool.id == "npm" {
            package["scripts"] = ["diskwing-cache-path": "\"$npm_node_execpath\" diskwing-cache-path.cjs"]
            try Data("process.stdout.write(process.env.npm_config_cache || '');\n".utf8).write(to: validation.appendingPathComponent("diskwing-cache-path.cjs"))
        }
        // Bun's package-manager commands also require a generated project.
        try JSONSerialization.data(withJSONObject: package, options: .sortedKeys).write(to: validation.appendingPathComponent("package.json"))
        if tool.id == "go" {
            // The Go command can initialize telemetry even for `env`. Give this
            // explicit validation a fresh home/config; it never reads user opt-in state.
            env = ["PATH": env["PATH"] ?? "/usr/bin:/bin", "HOME": validation.path,
                   "XDG_CONFIG_HOME": validation.appendingPathComponent("config").path,
                   "XDG_CACHE_HOME": validation.appendingPathComponent("cache").path,
                   "GOENV": "off", "GOTOOLCHAIN": "local", "GOPROXY": "off", "GOSUMDB": "off",
                   "GOPATH": validation.appendingPathComponent("gopath").path,
                   "GOCACHE": root.path, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        }
        let result = try CommandRunner.run(command, arguments, environment: env, timeout: 120, directory: validation)
        guard result.status == 0, !result.truncated else { throw CacheSSDError.message(L10n.text("A validação de \(tool.name) falhou. A origem foi preservada; código \(result.status).")) }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["npm", "go", "ccache"].contains(tool.id) {
            guard output.hasPrefix("/"), !output.contains("\n"), Paths.physicalURL(URL(fileURLWithPath: output)).path == Paths.physicalURL(root).path else { throw CacheSSDError.message(L10n.text("O destino efetivo não corresponde ao SSD preparado. A origem foi preservada.")) }
        }
        if tool.id == "yarn" {
            guard let version = CacheAdapters.yarnClassicVersion(home: home), output == version else { throw CacheSSDError.message(L10n.text("A versão do Yarn mudou. A origem e as cópias foram preservadas.")) }
        }
    }

    public func restore(toolID: String, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard let tool = CacheCatalog.find(toolID, home: home) else { throw CacheSSDError.message(L10n.text("Ferramenta desconhecida.")) }
        let settings = store.settings()
        guard let location = settings.locations[toolID], let volume = volumeProvider(location.volumeUUID) else { throw CacheSSDError.message(L10n.text("Conecte o SSD para restaurar a cópia. O cache local também pode ser recriado normalmente pela ferramenta.")) }
        guard location.relativePath.hasPrefix("MacCaches/CacheSSD/" + settings.installationID + "/" + toolID + "/"), location.relativePath.split(separator: "/").allSatisfy({ Paths.safeComponent(String($0)) }) else { throw CacheSSDError.message(L10n.text("Caminho de recuperação inválido.")) }
        let root = URL(fileURLWithPath: volume.path).appendingPathComponent(location.relativePath)
        let source = tool.payload(at: root)
        guard root.standardizedFileURL == root.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O caminho da cópia foi alterado.")) }
        guard try busyCheck([source, tool.source], toolID).isEmpty else { throw CacheSSDError.message(L10n.text("Encerre a ferramenta antes da restauração.")) }
        guard tool.source.standardizedFileURL == tool.source.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O cache local foi redirecionado.")) }
        let localSize = FileTree.measure(tool.source, cancellation: cancellation, progress: progress)
        guard (localSize.isComplete || localSize.missing), localSize.logical == 0 else { throw CacheSSDError.message(L10n.text("Já existe cache local. Use somente o Mac para preservá-lo; ele não será sobrescrito.")) }
        let externalSize = FileTree.measure(source, cancellation: cancellation, progress: progress)
        guard externalSize.isComplete else { throw CacheSSDError.message(L10n.text("A cópia no SSD não pode ser lida completamente.")) }
        guard Volumes.free(at: home) > externalSize.logical + 536_870_912 else { throw CacheSSDError.message(L10n.text("Não há espaço suficiente no Mac para restaurar esta cópia.")) }
        let operationID = UUID()
        let safety = try OperationContext(store: store, kind: "restore", source: source, destination: tool.source, toolID: toolID, id: operationID, sourceVolumeUUID: volume.uuid, checkpoint: checkpoint)
        let temp = tool.source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-restore-\(operationID.uuidString)")
        safety.journal.staging = temp.path
        do {
            try safety.advance(.verifying)
            let digest = try FileTree.digest(source, tool: toolID, cancellation: cancellation, workspace: store.base, progress: progress)
            safety.journal.sourceDigest = digest
            try safety.advance(.copying)
            try FileTree.copy(source, to: temp, tool: toolID, cancellation: cancellation, progress: progress)
            guard try FileTree.digest(temp, tool: toolID, cancellation: cancellation, workspace: store.base, progress: progress) == digest,
                  try FileTree.digest(source, tool: toolID, cancellation: cancellation, workspace: store.base, progress: progress) == digest else { throw CacheSSDError.message(L10n.text("A cópia mudou ou a restauração não passou pela conferência.")) }
            safety.journal.destinationDigest = digest
            try safety.advance(.copyVerified)
            guard try busyCheck([source, tool.source], toolID).isEmpty else { throw CacheSSDError.message(L10n.text("O cache passou a ser utilizado; a troca foi adiada.")) }
            if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Restauração cancelada; cópias preservadas.")) }
            try safety.advance(.publishing)
            try RestorePublication.publish(temp, to: tool.source, journal: &safety.journal, store: store)
            try safety.advance(.published)
            var latest = try store.read(AppSettings.self, name: "settings.json")
            if let active = latest.locations[toolID] {
                guard latest.installationID == settings.installationID, active.toolID == toolID,
                      active.volumeUUID == location.volumeUUID, active.relativePath == location.relativePath else { throw CacheSSDError.message(L10n.text("A restauração encontrou conteúdo ou configuração diferente. As cópias foram preservadas para revisão.")) }
                latest.locations.removeValue(forKey: toolID); try store.save(latest)
            }
            try store.append(OperationRecord(title: "\(tool.name) restaurado", detail: "Cache novamente no Mac. A cópia do SSD foi preservada.", recoveryPath: root.path))
            try safety.advance(.completed)
        } catch {
            safety.recordFailure(error, cancellation: cancellation); throw error
        }
    }
}

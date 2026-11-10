import Foundation
import Darwin
import CryptoKit

public struct VolumeRootIdentity: Codable, Equatable, Sendable {
    public let volumeUUID: String
    public let device: Int64
    public let inode: UInt64
    public var fileIdentity: FileIdentity { FileIdentity(device: device, inode: inode) }
    public init(volumeUUID: String, device: Int64, inode: UInt64) { self.volumeUUID = volumeUUID; self.device = device; self.inode = inode }
}

public struct VolumeScanRoot: Codable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case system, data, personal }
    public let id: String
    public let url: URL
    public let identity: VolumeRootIdentity
    public let role: Role
    public let isInternal: Bool
    public let isWritable: Bool
    public var volumeUUID: String { identity.volumeUUID }
    public init(url: URL, volumeUUID: String? = nil, role: Role = .personal, isInternal: Bool? = nil, isWritable: Bool? = nil) throws {
        guard VolumeScanRoot.unredirected(url) else { throw CacheSSDError.message("A raiz do volume está indisponível ou foi redirecionada.") }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message("Selecione uma raiz de volume disponível.") }
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsInternalKey, .volumeIsReadOnlyKey])
        guard let uuid = volumeUUID ?? values?.volumeUUIDString, !uuid.isEmpty else { throw CacheSSDError.message("Não foi possível confirmar a identidade do volume.") }
        self.id = uuid; self.url = url; self.role = role
        identity = VolumeRootIdentity(volumeUUID: uuid, device: Int64(metadata.st_dev), inode: UInt64(metadata.st_ino))
        self.isInternal = isInternal ?? values?.volumeIsInternal ?? false
        self.isWritable = isWritable ?? (!(values?.volumeIsReadOnly ?? true) && FileManager.default.isWritableFile(atPath: url.path))
    }
    static func unredirected(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for part in url.pathComponents.dropFirst() {
            guard part != ".", part != ".." else { return false }
            current.appendPathComponent(part)
            var metadata = stat()
            guard lstat(current.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else { return false }
        }
        return true
    }
    public func volumeInfo(name: String) -> VolumeInfo {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return VolumeInfo(uuid: volumeUUID, name: name, path: url.path, totalBytes: Int64(values?.volumeTotalCapacity ?? 0), freeBytes: Volumes.free(at: url), isInternal: isInternal, isWritable: isWritable)
    }
}

public struct VolumeScanTarget: Codable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let roots: [VolumeScanRoot]
    public let displayRoot: URL
    public let dataNamespace: String
    public var isSystemGroup: Bool { roots.contains { $0.role == .system } && roots.contains { $0.role == .data } }
    public init(id: String, name: String, roots: [VolumeScanRoot], displayRoot: URL? = nil, dataNamespace: String? = nil) throws {
        guard !id.isEmpty, roots.count == 1 || roots.count == 2 && Set(roots.map { $0.role.rawValue }) == Set(["system", "data"]), Set(roots.map(\.id)).count == roots.count else { throw CacheSSDError.message("A seleção de volumes é inválida.") }
        schemaVersion = 1; self.id = id; self.name = name; self.roots = roots
        let expectedRoot = roots.first(where: { $0.role == .system })?.url ?? roots[0].url
        let chosenRoot = displayRoot ?? expectedRoot
        guard chosenRoot.isFileURL, chosenRoot.path == expectedRoot.path else { throw CacheSSDError.message("A raiz exibida não corresponde ao volume selecionado.") }
        self.displayRoot = chosenRoot
        let suffix = SHA256.hash(data: Data(id.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        var namespace = dataNamespace ?? VolumeScanner.otherData + "-" + suffix
        if dataNamespace == nil {
            var metadata = stat()
            while lstat(self.displayRoot.appendingPathComponent(namespace).path, &metadata) == 0 { namespace += "-" }
        }
        guard Paths.safeComponent(namespace) else { throw CacheSSDError.message("A seleção de volumes é inválida.") }
        self.dataNamespace = namespace
    }
    func validateStructure() throws {
        guard schemaVersion == 1, !id.isEmpty, displayRoot.isFileURL, Paths.safeComponent(dataNamespace),
              roots.count == 1 || roots.count == 2 && Set(roots.map { $0.role.rawValue }) == Set(["system", "data"]),
              Set(roots.map(\.id)).count == roots.count, roots.allSatisfy({ $0.url.isFileURL && $0.id == $0.volumeUUID && !$0.id.isEmpty }) else { throw CacheSSDError.message("A seleção de volumes é inválida ou pertence a uma versão mais recente.") }
        let expectedRoot = roots.first(where: { $0.role == .system })?.url ?? roots[0].url
        guard displayRoot.path == expectedRoot.path else { throw CacheSSDError.message("A raiz exibida não corresponde ao volume selecionado.") }
    }
    public static func folder(_ url: URL, name: String? = nil) throws -> VolumeScanTarget {
        let root = try VolumeScanRoot(url: Paths.physicalURL(url))
        return try VolumeScanTarget(id: root.volumeUUID + ":" + root.url.path, name: name ?? url.lastPathComponent, roots: [root])
    }
}

public struct VolumeSourceLocation: Sendable {
    public let root: VolumeScanRoot
    public let relativePath: String
    public let url: URL
    public let physicalURL: URL
    public var rootID: String { root.id }
    public var volumeUUID: String { root.volumeUUID }
    public var rootIdentity: VolumeRootIdentity { root.identity }
}

public struct VolumeIndexLocation: Sendable {
    public let url: URL
    public let policy: IndexStoragePolicy
    public let storageVolumeUUID: String?
    public let storageRoot: VolumeScanRoot
    public var canonicalRootIdentity: VolumeRootIdentity { storageRoot.identity }
    public func validateStorage(volumeIdentifier: (URL) -> String = IndexStoragePolicy.volumeIdentifier) throws {
        var metadata = stat()
        guard VolumeScanRoot.unredirected(storageRoot.url), lstat(storageRoot.url.path, &metadata) == 0,
              Int64(metadata.st_dev) == storageRoot.identity.device, UInt64(metadata.st_ino) == storageRoot.identity.inode,
              volumeIdentifier(storageRoot.url).caseInsensitiveCompare(storageRoot.volumeUUID) == .orderedSame,
              FileManager.default.isWritableFile(atPath: storageRoot.url.path) else { throw CacheSSDError.message("O volume do índice mudou ou está indisponível. Nenhuma pasta substituta foi criada no Mac.") }
    }
    public func openIndex(createIfMissing: Bool = true, volumeIdentifier: @escaping (URL) -> String = IndexStoragePolicy.volumeIdentifier) throws -> ScanIndex {
        try validateStorage(volumeIdentifier: volumeIdentifier)
        guard Paths.contains(url, in: storageRoot.url), url.path != storageRoot.url.path else { throw CacheSSDError.message("O índice não pertence ao volume escolhido.") }
        let relative = String(url.path.dropFirst(storageRoot.url.path == "/" ? 1 : storageRoot.url.path.count + 1))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(Paths.safeComponent), let filename = parts.last else { throw CacheSSDError.message("O caminho do índice é inválido.") }
        var rootFD = open(storageRoot.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw CacheSSDError.message("O volume do índice está indisponível.") }
        var parentFD = dup(rootFD), fileFD: Int32 = -1
        var directoryProofs: [(Int32, String, FileIdentity)] = []
        defer { if rootFD >= 0 { close(rootFD) }; if parentFD >= 0 { close(parentFD) }; if fileFD >= 0 { close(fileFD) }; for proof in directoryProofs { close(proof.0) } }
        var rootMetadata = stat()
        guard parentFD >= 0, fstat(rootFD, &rootMetadata) == 0, Int64(rootMetadata.st_dev) == storageRoot.identity.device, UInt64(rootMetadata.st_ino) == storageRoot.identity.inode else { throw CacheSSDError.message("A identidade do volume do índice mudou.") }
        for component in parts.dropLast() {
            try validateStorage(volumeIdentifier: volumeIdentifier)
            if createIfMissing { guard mkdirat(parentFD, component, 0o700) == 0 || errno == EEXIST else { throw CacheSSDError.message("Não foi possível preparar a pasta privada do índice.") } }
            let next = openat(parentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw CacheSSDError.message("A pasta do índice está ausente ou foi redirecionada.") }
            var metadata = stat()
            guard fstat(next, &metadata) == 0, Int64(metadata.st_dev) == storageRoot.identity.device else { close(next); throw CacheSSDError.message("A pasta do índice pertence a outro volume.") }
            let proofFD = dup(parentFD)
            guard proofFD >= 0 else { close(next); throw CacheSSDError.message("Não foi possível preservar a identidade da pasta do índice.") }
            directoryProofs.append((proofFD, component, FileIdentity(device: Int64(metadata.st_dev), inode: UInt64(metadata.st_ino))))
            close(parentFD); parentFD = next
        }
        try validateStorage(volumeIdentifier: volumeIdentifier)
        fileFD = openat(parentFD, filename, (createIfMissing ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (createIfMissing ? O_CREAT : 0), 0o600)
        var fileMetadata = stat(), parentMetadata = stat()
        guard fileFD >= 0, fstat(fileFD, &fileMetadata) == 0, fileMetadata.st_mode & S_IFMT == S_IFREG, fileMetadata.st_nlink == 1,
              Int64(fileMetadata.st_dev) == storageRoot.identity.device, fstat(parentFD, &parentMetadata) == 0 else { throw CacheSSDError.message("O índice está ausente, foi redirecionado ou não é um arquivo privado regular.") }
        if createIfMissing { guard fchmod(fileFD, 0o600) == 0 else { throw CacheSSDError.message("Não foi possível proteger o índice privado.") } }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fileFD, F_GETPATH, &path) == 0 else { throw CacheSSDError.message("Não foi possível confirmar o arquivo do índice.") }
        let openingURL = URL(fileURLWithPath: String(cString: path))
        let anchor = VolumeIndexAnchor(location: self, rootFD: rootFD, parentFD: parentFD, fileFD: fileFD,
                                       parentIdentity: FileIdentity(device: Int64(parentMetadata.st_dev), inode: UInt64(parentMetadata.st_ino)),
                                       fileIdentity: FileIdentity(device: Int64(fileMetadata.st_dev), inode: UInt64(fileMetadata.st_ino)), directoryProofs: directoryProofs, volumeIdentifier: volumeIdentifier)
        rootFD = -1; parentFD = -1; fileFD = -1
        directoryProofs = []
        try anchor.validate(forceIdentity: true)
        let index = try ScanIndex(url: url, openingURL: openingURL, expectedDatabase: anchor.fileIdentity, storageValidation: { force in try anchor.validate(forceIdentity: force) }, prepareParent: false, metadataLookupOnly: !createIfMissing)
        do { if createIfMissing { try index.prepareVolumeTables() }; return index }
        catch { try? index.close(); throw error }
    }
}

private final class VolumeIndexAnchor {
    let location: VolumeIndexLocation
    let rootFD: Int32, parentFD: Int32, fileFD: Int32
    let parentIdentity: FileIdentity, fileIdentity: FileIdentity
    let directoryProofs: [(Int32, String, FileIdentity)]
    let volumeIdentifier: (URL) -> String
    init(location: VolumeIndexLocation, rootFD: Int32, parentFD: Int32, fileFD: Int32, parentIdentity: FileIdentity, fileIdentity: FileIdentity, directoryProofs: [(Int32, String, FileIdentity)], volumeIdentifier: @escaping (URL) -> String) {
        self.location = location; self.rootFD = rootFD; self.parentFD = parentFD; self.fileFD = fileFD
        self.parentIdentity = parentIdentity; self.fileIdentity = fileIdentity; self.volumeIdentifier = volumeIdentifier; self.directoryProofs = directoryProofs
    }
    deinit { close(fileFD); close(parentFD); close(rootFD); for proof in directoryProofs { close(proof.0) } }
    func validate(forceIdentity: Bool) throws {
        for proof in directoryProofs {
            var metadata = stat()
            guard fstatat(proof.0, proof.1, &metadata, AT_SYMLINK_NOFOLLOW) == 0, metadata.st_mode & S_IFMT == S_IFDIR, Int64(metadata.st_dev) == proof.2.device, UInt64(metadata.st_ino) == proof.2.inode else { throw CacheSSDError.message("Uma pasta do índice mudou ou foi redirecionada.") }
        }
        var root = stat(), parent = stat(), file = stat(), currentRoot = stat(), currentFile = stat()
        let expected = location.storageRoot.identity
        guard fstat(rootFD, &root) == 0, fstat(parentFD, &parent) == 0, fstat(fileFD, &file) == 0,
              lstat(location.storageRoot.url.path, &currentRoot) == 0, fstatat(parentFD, location.url.lastPathComponent, &currentFile, AT_SYMLINK_NOFOLLOW) == 0,
              Int64(root.st_dev) == expected.device, UInt64(root.st_ino) == expected.inode,
              currentRoot.st_dev == root.st_dev, currentRoot.st_ino == root.st_ino, currentRoot.st_mode & S_IFMT == S_IFDIR,
              Int64(parent.st_dev) == parentIdentity.device, UInt64(parent.st_ino) == parentIdentity.inode,
              Int64(file.st_dev) == fileIdentity.device, UInt64(file.st_ino) == fileIdentity.inode,
              currentFile.st_dev == file.st_dev, currentFile.st_ino == file.st_ino, currentFile.st_mode & S_IFMT == S_IFREG,
              file.st_nlink == 1, volumeIdentifier(location.storageRoot.url).caseInsensitiveCompare(expected.volumeUUID) == .orderedSame else { throw CacheSSDError.message("O armazenamento do índice mudou. A conexão foi preservada sem criar substitutos.") }
        if forceIdentity {
            var filesystem = statfs()
            guard VolumeScanRoot.unredirected(location.storageRoot.url), fstatfs(rootFD, &filesystem) == 0, filesystem.f_flags & UInt32(MNT_RDONLY) == 0 else { throw CacheSSDError.message("O volume do índice está indisponível ou não permite escrita.") }
        }
    }
}

public struct IndexStoragePolicy: Codable, Equatable, Sendable {
    private final class UUIDAliases: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: String] = [:]
        func resolve(native: String, at url: URL) -> String {
            lock.lock(); let cached = values[native]; lock.unlock()
            if let cached { return cached }
            var fresh = URL(fileURLWithPath: url.path, isDirectory: true)
            fresh.removeAllCachedResourceValues()
            // The sealed boot snapshot's native UUID can differ from the
            // logical volume UUID used by Foundation/VolumeInfo. Key this
            // equivalence by native UUID, never a mutable mountpoint or name.
            let logical = (try? fresh.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? native
            lock.lock()
            if values.count >= 128 { values.removeAll(keepingCapacity: true) }
            values[native] = logical
            lock.unlock()
            return logical
        }
    }
    private static let aliases = UUIDAliases()
    public let maximumBytes: Int64?
    public let minimumFreeBytes: Int64
    public static let internalStorage = IndexStoragePolicy(maximumBytes: 536_870_912, minimumFreeBytes: 268_435_456)
    public static let externalSSD = IndexStoragePolicy(maximumBytes: nil, minimumFreeBytes: 1_073_741_824)
    public init(maximumBytes: Int64?, minimumFreeBytes: Int64) { self.maximumBytes = maximumBytes; self.minimumFreeBytes = max(0, minimumFreeBytes) }
    public static func filesystemType(_ url: URL) -> String {
        var metadata = statfs()
        guard statfs(url.path, &metadata) == 0 else { return "" }
        return withUnsafePointer(to: &metadata.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) } }
    }
    public static func volumeIdentifier(_ url: URL) -> String {
        struct VolumeUUIDBuffer { var length: UInt32 = 0; var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) }
        var attributes = attrlist(), result = VolumeUUIDBuffer()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT); attributes.volattr = UInt32(ATTR_VOL_INFO) | UInt32(ATTR_VOL_UUID)
        if getattrlist(url.path, &attributes, &result, MemoryLayout<VolumeUUIDBuffer>.size, 0) == 0, result.length >= MemoryLayout<VolumeUUIDBuffer>.size {
            let uuid = UUID(uuid: result.uuid).uuidString
            if uuid != "00000000-0000-0000-0000-000000000000" { return aliases.resolve(native: uuid, at: url) }
        }
        var fresh = URL(fileURLWithPath: url.path, isDirectory: true)
        fresh.removeAllCachedResourceValues()
        return (try? fresh.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? ""
    }
    public static func location(internalDirectory: URL, externalVolume: VolumeInfo? = nil, installationID: String, targetID: String,
                                filesystemType: (URL) -> String = IndexStoragePolicy.filesystemType,
                                volumeIdentifier: (URL) -> String = IndexStoragePolicy.volumeIdentifier,
                                freeBytes: (URL) -> Int64 = Volumes.free) throws -> VolumeIndexLocation {
        let name = SHA256.hash(data: Data(targetID.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let volume = externalVolume else {
            var anchor = internalDirectory, metadata = stat()
            while lstat(anchor.path, &metadata) != 0 {
                guard errno == ENOENT, anchor.path != "/" else { throw CacheSSDError.message("A pasta interna dos índices está indisponível.") }
                anchor.deleteLastPathComponent()
            }
            let binding = try VolumeScanRoot(url: anchor, volumeUUID: volumeIdentifier(anchor), isInternal: true)
            return VolumeIndexLocation(url: internalDirectory.appendingPathComponent("volume-index-\(name).sqlite"), policy: .internalStorage, storageVolumeUUID: nil, storageRoot: binding)
        }
        let root = URL(fileURLWithPath: volume.path, isDirectory: true)
        guard Paths.safeComponent(installationID), !volume.isInternal, volume.isWritable, VolumeScanRoot.unredirected(root),
              filesystemType(root).lowercased() == "apfs", volumeIdentifier(root).caseInsensitiveCompare(volume.uuid) == .orderedSame,
              FileManager.default.isWritableFile(atPath: root.path), freeBytes(root) >= externalSSD.minimumFreeBytes else { throw CacheSSDError.message("O SSD escolhido para os índices está indisponível ou não é APFS. Nenhum índice interno foi substituído.") }
        let directory = root.appendingPathComponent("MacCaches/CacheSSD/\(installationID)/Indexes")
        var current = root
        for component in ["MacCaches", "CacheSSD", installationID, "Indexes"] {
            current.appendPathComponent(component)
            var metadata = stat()
            if lstat(current.path, &metadata) != 0 {
                guard errno == ENOENT else { throw CacheSSDError.message("A pasta dos índices está indisponível.") }
                break
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message("A pasta dos índices foi redirecionada ou não é uma pasta.") }
        }
        let binding = try VolumeScanRoot(url: root, volumeUUID: volume.uuid, isInternal: false, isWritable: true)
        return VolumeIndexLocation(url: directory.appendingPathComponent("\(name).sqlite"), policy: .externalSSD, storageVolumeUUID: volume.uuid, storageRoot: binding)
    }
}

public struct VolumeDiscoveryMetadata: Sendable {
    public let groupID: String?
    public init(groupID: String?) { self.groupID = groupID }
}

extension Volumes {
    public static func scanMetadata(_ url: URL) -> VolumeDiscoveryMetadata? {
        guard let result = try? CommandRunner.run(URL(fileURLWithPath: "/usr/sbin/diskutil"), ["info", "-plist", url.path], timeout: 10, maxOutputBytes: 1_048_576), result.status == 0,
              let value = try? PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any] else { return nil }
        return VolumeDiscoveryMetadata(groupID: value["APFSVolumeGroupID"] as? String)
    }
    public static func scanTargets(volumes: [VolumeInfo] = Volumes.list(), systemRoot: URL = URL(fileURLWithPath: "/", isDirectory: true), dataRoot: URL = DataVolumePaths.dataRoot,
                                   metadata: (URL) -> VolumeDiscoveryMetadata? = Volumes.scanMetadata,
                                   volumeIdentifier: (URL) -> String = IndexStoragePolicy.volumeIdentifier) -> [VolumeScanTarget] {
        var targets: [VolumeScanTarget] = [], grouped = Set<String>()
        if let systemGroup = metadata(systemRoot)?.groupID, !systemGroup.isEmpty, metadata(dataRoot)?.groupID == systemGroup,
           let system = try? VolumeScanRoot(url: systemRoot, volumeUUID: volumeIdentifier(systemRoot), role: .system), let data = try? VolumeScanRoot(url: dataRoot, volumeUUID: volumeIdentifier(dataRoot), role: .data),
           let target = try? VolumeScanTarget(id: "apfs-group:" + systemGroup, name: volumes.first(where: { $0.path == systemRoot.path })?.name ?? "Macintosh HD", roots: [system, data], displayRoot: systemRoot) {
            targets.append(target); grouped.formUnion([system.volumeUUID, data.volumeUUID])
        }
        for volume in volumes where !grouped.contains(volume.uuid) {
            guard let root = try? VolumeScanRoot(url: URL(fileURLWithPath: volume.path, isDirectory: true), volumeUUID: volume.uuid, role: volume.path == systemRoot.path ? .system : .personal, isInternal: volume.isInternal, isWritable: volume.isWritable),
                  let target = try? VolumeScanTarget(id: volume.uuid, name: root.role == .system ? volume.name + " — Sistema" : volume.name, roots: [root]) else { continue }
            targets.append(target)
        }
        if grouped.isEmpty, metadata(dataRoot) != nil, let data = try? VolumeScanRoot(url: dataRoot, volumeUUID: volumeIdentifier(dataRoot), role: .data), !targets.contains(where: { $0.roots.contains { $0.volumeUUID == data.volumeUUID } }),
           let target = try? VolumeScanTarget(id: data.volumeUUID, name: "Dados do armazenamento interno", roots: [data]) { targets.append(target) }
        return targets
    }
}

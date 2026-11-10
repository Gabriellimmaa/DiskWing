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
}

public struct IndexStoragePolicy: Codable, Equatable, Sendable {
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
    public static func volumeIdentifier(_ url: URL) -> String { (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? "" }
    public static func location(internalDirectory: URL, externalVolume: VolumeInfo? = nil, installationID: String, targetID: String,
                                filesystemType: (URL) -> String = IndexStoragePolicy.filesystemType,
                                volumeIdentifier: (URL) -> String = IndexStoragePolicy.volumeIdentifier,
                                freeBytes: (URL) -> Int64 = Volumes.free) throws -> VolumeIndexLocation {
        let name = SHA256.hash(data: Data(targetID.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let volume = externalVolume else { return VolumeIndexLocation(url: internalDirectory.appendingPathComponent("volume-index-\(name).sqlite"), policy: .internalStorage, storageVolumeUUID: nil) }
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
        return VolumeIndexLocation(url: directory.appendingPathComponent("\(name).sqlite"), policy: .externalSSD, storageVolumeUUID: volume.uuid)
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

import Foundation
import Darwin

public struct UpdateSafetyState: Equatable, Sendable {
    public var workInProgress: Bool
    public var pendingRecovery: Bool
    public var unreadableRecords: Bool
    public var pendingConfiguration: Bool
    public init(workInProgress: Bool = false, pendingRecovery: Bool = false, unreadableRecords: Bool = false, pendingConfiguration: Bool = false) {
        self.workInProgress = workInProgress; self.pendingRecovery = pendingRecovery
        self.unreadableRecords = unreadableRecords; self.pendingConfiguration = pendingConfiguration
    }
    public var isIdle: Bool { !workInProgress && !pendingRecovery && !unreadableRecords && !pendingConfiguration }
}

public enum UpdatePolicy {
    public static let automaticDownloads = false
    public static let systemProfiling = false
    public static func canCheck(automatic: Bool, consent: Bool, state: UpdateSafetyState) -> Bool {
        state.isIdle && (!automatic || consent)
    }
    public static func canInstall(state: UpdateSafetyState) -> Bool { state.isIdle }
}

/// Holds the same cross-process lease as file operations throughout an update.
/// Read/re-read recovery state while holding it, never before acquiring it.
public final class UpdateSessionLease {
    private let lease: OperationLease
    private let store: Store
    private let isBusy: () -> Bool
    public init(store: Store, isBusy: @escaping () -> Bool) throws {
        self.store = store; self.isBusy = isBusy
        lease = try OperationLease(store: store)
        try revalidate()
    }
    public func revalidate() throws {
        // Store's historical convenience readers return [] on a listing error.
        // An updater must not mistake that error for verified idle state.
        let names = try FileManager.default.contentsOfDirectory(atPath: store.base.path)
        var pending = false, unreadable = false, configuration = false
        for name in names where name.hasSuffix(".json") {
            if name.hasPrefix("operation-") {
                do {
                    let record: OperationJournal = try readRecord(name)
                    if record.schemaVersion != 1 || record.hasUnsupportedVolumeTrashScope { unreadable = true }
                    else { pending = pending || record.isPending }
                } catch { unreadable = true }
            } else if name.hasPrefix("configuration-") {
                do {
                    let record: ConfigurationChange = try readRecord(name)
                    if record.schemaVersion != 1 { unreadable = true }
                    else { configuration = configuration || record.state != "completed" }
                } catch { unreadable = true }
            }
        }
        let graphicalUnsafe = GraphicalCacheMigrationEngine(store: store).hasUnsafeRecoveryRecords()
        let state = UpdateSafetyState(workInProgress: isBusy(), pendingRecovery: pending,
                                      unreadableRecords: unreadable || graphicalUnsafe, pendingConfiguration: configuration)
        guard UpdatePolicy.canInstall(state: state) else { throw CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }
        withExtendedLifetime(lease) {}
    }
    private func readRecord<T: Decodable>(_ name: String) throws -> T {
        let path = store.base.appendingPathComponent(name).path
        var before = stat()
        guard lstat(path, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_flags & UInt32(SF_DATALESS) == 0, before.st_size <= 8_388_608 else { throw blocked() }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw blocked() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == before.st_dev, opened.st_ino == before.st_ino,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_flags & UInt32(SF_DATALESS) == 0,
              opened.st_size <= 8_388_608 else { throw blocked() }
        let bytes = try file.read(upToCount: 8_388_609) ?? Data()
        guard bytes.count <= 8_388_608 else { throw blocked() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: bytes)
    }
    private func blocked() -> Error { CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }

}

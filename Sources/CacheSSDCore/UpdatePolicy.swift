import Foundation

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
        _ = try FileManager.default.contentsOfDirectory(atPath: store.base.path)
        let state = UpdateSafetyState(workInProgress: isBusy(), pendingRecovery: store.operations().contains(where: \.isPending),
                                      unreadableRecords: !store.unreadableOperationRecords().isEmpty,
                                      pendingConfiguration: !store.pendingConfigurationRecords().isEmpty)
        guard UpdatePolicy.canInstall(state: state) else { throw CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }
        withExtendedLifetime(lease) {}
    }
}

import Foundation
import Combine
import AppKit
import CacheSSDCore
#if DISKWING_UPDATER
import Sparkle
#endif

@MainActor final class Updates: NSObject, ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var sessionInProgress = false
    @Published var enabled = false
    var operationInProgress: () -> Bool = { true }
    private let store = Store()
#if DISKWING_UPDATER
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var deferredInstall: (() -> Void)?
    private var timer: Timer?
    private var updateLease: OperationLease?
#endif
    override init() {
        super.init()
#if DISKWING_UPDATER
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        available = true
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller?.updater.publisher(for: \.sessionInProgress).sink { [weak self] value in
            self?.sessionInProgress = value
            if !value { self?.updateLease = nil }
        }
        enabled = UserDefaults.standard.bool(forKey: "DiskWingUpdateChecksConsent")
        if enabled { start(); controller?.updater.automaticallyChecksForUpdates = true }
#endif
    }
    func consent(_ value: Bool) {
        guard available else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "DiskWingUpdateChecksConsent")
#if DISKWING_UPDATER
        if value { start() }
        controller?.updater.automaticallyChecksForUpdates = value
#endif
    }
    func check() {
#if DISKWING_UPDATER
        guard available, !operationInProgress(), !sessionInProgress else { return }
        start(); controller?.checkForUpdates(nil)
#endif
    }
#if DISKWING_UPDATER
    private var started = false
    private func start() {
        guard !started else { return }; started = true
        controller?.updater.automaticallyDownloadsUpdates = false
        controller?.updater.sendsSystemProfile = false
        controller?.startUpdater()
    }
    private func requireIdle() throws {
        guard !operationInProgress(), !store.operations().contains(where: \.isPending), store.unreadableOperationRecords().isEmpty, store.pendingConfigurationRecords().isEmpty else { throw CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }
        if updateLease == nil { updateLease = try OperationLease(store: store) }
    }
#endif
}

#if DISKWING_UPDATER
extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws { try requireIdle() }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws { try requireIdle() }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard (try? requireIdle()) == nil else { return false }
        deferredInstall = installHandler
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, (try? self.requireIdle()) != nil else { return }
                self.timer?.invalidate(); self.timer = nil
                let install = self.deferredInstall; self.deferredInstall = nil; install?()
            }
        }
        return true
    }
}
#endif

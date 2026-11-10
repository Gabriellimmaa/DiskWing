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
    private let store: Store
    private let disabled: Bool
    private var updateLease: UpdateSessionLease?
#if DISKWING_UPDATER
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var deferredInstall: (() -> Void)?
    private var timer: Timer?
#endif
    init(store: Store, disabled: Bool = false) {
        self.store = store
        self.disabled = disabled
        super.init()
        guard !disabled else { return }
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
        guard available, !sessionInProgress, UpdatePolicy.canCheck(automatic: false, consent: enabled, state: UpdateSafetyState(workInProgress: operationInProgress())) else { return }
        guard (try? requireIdle()) != nil else { return }
        start(); controller?.checkForUpdates(nil)
#endif
    }
#if DISKWING_UPDATER
    private var started = false
    private func start() {
        guard !started else { return }; started = true
        controller?.updater.automaticallyChecksForUpdates = enabled
        controller?.updater.automaticallyDownloadsUpdates = UpdatePolicy.automaticDownloads
        controller?.updater.sendsSystemProfile = UpdatePolicy.systemProfiling
        controller?.startUpdater()
    }
#endif
    /// Kept outside the optional Sparkle compilation so the GUI bridge's lock
    /// ordering and failure cleanup are directly testable without a feed.
    func requireIdle() throws {
        guard !disabled else { throw CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }
        do {
            if let updateLease { try updateLease.revalidate() }
            else { updateLease = try UpdateSessionLease(store: store, isBusy: { [weak self] in self?.operationInProgress() ?? true }) }
        } catch { updateLease = nil; throw error }
    }
}

#if DISKWING_UPDATER
extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard UpdatePolicy.canCheck(automatic: updateCheck != .updates, consent: enabled, state: UpdateSafetyState(workInProgress: operationInProgress())) else { throw CacheSSDError.message(L10n.text("Conclua a operação ou recuperação antes de atualizar o aplicativo.")) }
        try requireIdle()
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws { try requireIdle() }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if deferredInstall == nil { updateLease = nil }
    }
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

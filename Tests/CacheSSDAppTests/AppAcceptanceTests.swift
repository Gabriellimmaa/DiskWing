import XCTest
import Foundation
import AppKit
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class AppAcceptanceTests: XCTestCase {
    func fixture(rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) throws -> (URL, AppContext) {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-app-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, try AppContext.makeSamples(workspace: root, rescanDelay: rescanDelay, rescanInterval: rescanInterval))
    }
    func wait(_ message: String = "App operation", until condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), message)
    }
    func testConsentIsPerReviewAndConfirmationKeepsExplicitChoice() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.refreshInventory()
        try await wait(until: { !model.inventoryRunning })
        let npm = try XCTUnwrap(model.tools.first { $0.id == "npm" }), pip = try XCTUnwrap(model.tools.first { $0.id == "pip" })
        model.review = .migration(npm); model.releaseLocal = true; model.review = nil
        XCTAssertFalse(model.releaseLocal)
        model.review = .migration(npm); XCTAssertFalse(model.releaseLocal)
        model.releaseLocal = true; model.review = .migration(pip); XCTAssertFalse(model.releaseLocal)
        model.review = .migration(npm); model.releaseLocal = true; model.execute(.migration(npm))
        XCTAssertFalse(model.releaseLocal)
        try await wait(until: { !model.busy })
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(FileTree.measure(npm.source).logical, 0, "Explicit reviewed release must survive closing the sheet")
        let bun = try XCTUnwrap(model.tools.first { $0.id == "bun" })
        let before = try FileTree.digest(bun.source, workspace: context.store.base)
        model.review = .migration(bun); model.releaseLocal = true; model.execute(.migration(bun))
        try await wait(until: { !model.busy })
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try FileTree.digest(bun.source, workspace: context.store.base), before)
    }
    func testExplorerPaginationSearchExportAndOutsideTargetsStayIsolated() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.chooseFolder()
        try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        XCTAssertNil(model.errorMessage); XCTAssertEqual(model.visibleItems.count, 120)
        model.nextPage(); try await wait(until: { !model.indexLoading }); XCTAssertEqual(model.indexOffset, 120)
        model.search = "find-me"; try await wait(until: { !model.indexLoading }); XCTAssertEqual(model.visibleItems.map(\.name), ["find-me.txt"])
        let output = try XCTUnwrap(context.container).appendingPathComponent("report.json")
        model.exportReport(to: output); try await wait(until: { !model.busy })
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String:Any])
        XCTAssertEqual(document["schemaVersion"] as? Int, 2)
        XCTAssertEqual((document["session"] as? [String:Any])?["volumeUUID"] as? String, "DISKWING-SAMPLE-FILESYSTEM")
        XCTAssertNotNil((document["entries"] as? [[String:Any]])?.first?["coverage"])
        let outside = root.appendingPathComponent("outside.json")
        model.exportReport(to: outside); XCTAssertNotNil(model.errorMessage); XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        model.errorMessage = nil; model.scan(root); XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.isScanning)
        let link = context.home.appendingPathComponent("Downloads/escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertFalse(context.allows(link)); XCTAssertFalse(context.allows(link.appendingPathComponent("outside.json")))
        XCTAssertThrowsError(try context.reveal([root])); XCTAssertThrowsError(try context.open(outside))
        XCTAssertTrue(try XCTUnwrap(context.samples).events.isEmpty)
    }
    func testSampleSessionResumeRequiresPrivateMarkedUnredirectedData() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let session = try XCTUnwrap(context.container)
        XCTAssertTrue(try AppContext.forLaunch(arguments: ["DiskWing", "--acceptance-session", session.path]).isSamples)
        XCTAssertThrowsError(try AppContext.forLaunch(arguments: ["DiskWing"], bundleIdentifier: "com.cachessd.app.acceptance"))
        XCTAssertThrowsError(try AppContext.forLaunch(arguments: ["DiskWing", "--acceptance-session", session.path], bundleIdentifier: "com.cachessd.app"))
        for args in [["DiskWing", "--acceptance-workspace"], ["DiskWing", "--acceptance-unknown", root.path], ["DiskWing", "--acceptance-session", root.path]] { XCTAssertThrowsError(try AppContext.forLaunch(arguments: args)) }
        let marker = session.appendingPathComponent(".diskwing-sample-session")
        try Data("unknown-version".utf8).write(to: marker)
        XCTAssertThrowsError(try AppContext.resumeSamples(session: session))
        XCTAssertEqual(try String(contentsOf: marker), "unknown-version")
        try Data("diskwing-gui-samples-v1\n".utf8).write(to: marker)
        let settings = context.store.base.appendingPathComponent("settings.json"), saved = try Data(contentsOf: settings)
        let outside = root.appendingPathComponent("keep.json"); try saved.write(to: outside)
        try FileManager.default.removeItem(at: settings); try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: outside)
        XCTAssertThrowsError(try AppContext.resumeSamples(session: session)); XCTAssertEqual(try Data(contentsOf: outside), saved)
    }
    func testPendingRecoveryIsVisibleOnOverviewAndUsesOnlySampleCopy() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let source = context.home.appendingPathComponent("Downloads/sample-001.txt"), destination = try XCTUnwrap(context.container).appendingPathComponent("personal-destination/sample-001.txt")
        let expected = try FileTree.digest(source, workspace: context.store.base)
        var journal = try OperationJournal(kind: "personalMove", source: source, destination: destination)
        try FileTree.copyItem(source, to: destination)
        journal.sourceDigest = expected; journal.destinationDigest = expected; journal.phase = .interrupted
        try context.store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
        try FileManager.default.moveItem(at: source, to: try XCTUnwrap(context.container).appendingPathComponent("preserved-original.txt"))
        let resumed = try AppContext.resumeSamples(session: XCTUnwrap(context.container)), model = AppModel(context: resumed)
        XCTAssertEqual(model.section, .explorer); XCTAssertEqual(model.pendingRecoveryCount, 1)
        let assessment = try XCTUnwrap(model.recoveries.first); XCTAssertTrue(assessment.canRestoreSource)
        model.review = .recover(assessment); model.execute(.recover(assessment)); try await wait(until: { !model.busy })
        XCTAssertNil(model.errorMessage); XCTAssertEqual(model.pendingRecoveryCount, 0)
        XCTAssertEqual(try FileTree.digest(source, workspace: context.store.base), expected)
        XCTAssertEqual(try FileTree.digest(destination, workspace: context.store.base), expected)
    }
    func testSystemServicesAndSSDDisconnectionAreSimulated() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context), state = try XCTUnwrap(context.samples)
        XCTAssertFalse(model.updates.available); model.updates.consent(true); XCTAssertFalse(model.updates.enabled)
        model.setLogin(true); XCTAssertTrue(state.loginEnabled)
        model.setGrowthAlerts(true); try await wait(until: { model.preferences.growthAlerts })
        model.openPrivacy(); model.reveal([context.home])
        model.review = .xcodeLocal; model.execute(.xcodeLocal); try await wait(until: { !model.busy })
        let volume = try XCTUnwrap(model.selectedVolume); model.review = .eject(volume); model.execute(.eject(volume)); try await wait(until: { !model.busy })
        XCTAssertFalse(state.volumeConnected); XCTAssertNil(model.selectedVolume)
        XCTAssertEqual(Set(state.events), Set(["login", "notification-permission", "privacy", "reveal", "xcode-local", "eject"]))
    }
    func testLowPowerPauseResumesPendingScanWhenSimulationChanges() async throws {
        let (root, context) = try fixture(rescanDelay: 0.02, rescanInterval: 0.02)
        defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context), state = try XCTUnwrap(context.samples)
        model.chooseFolder(); try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let previous = try XCTUnwrap(model.report?.id), scope = try XCTUnwrap(model.report?.root.url)
        model.watchCurrentRoot(true); state.lowPower = true
        model.scheduleRescan(scope, full: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.report?.id, previous); XCTAssertFalse(model.isScanning)
        state.lowPower = false
        try await wait(until: { model.report?.id != previous && !model.isScanning })
        XCTAssertNil(model.errorMessage)
    }
    func testSimulatedExternalScopeBecomesUnavailableWithoutFalseGrowth() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let scope = try XCTUnwrap(context.container).appendingPathComponent("sample-ssd"), state = try XCTUnwrap(context.samples)
        try Data("generated".utf8).write(to: scope.appendingPathComponent("file"))
        let model = AppModel(context: context); model.scan(scope)
        try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let first = model.report?.id
        model.scan(scope)
        try await wait(until: { model.report?.id != first && !model.isScanning && model.growthComparison?.state == "comparable" })
        model.watchCurrentRoot(true)
        XCTAssertEqual(model.preferences.watchedFolders.first?.volumeUUID, "DISKWING-SAMPLE-EXTERNAL-FILESYSTEM")
        let previous = model.report?.id; try state.setVolumeConnected(false)
        XCTAssertFalse(model.currentScopeAvailable); XCTAssertNil(model.growthComparison)
        XCTAssertTrue(context.scanVolumeIdentifier()(scope).isEmpty)
        model.scan(scope); XCTAssertFalse(model.isScanning); XCTAssertEqual(model.report?.id, previous)
        try state.setVolumeConnected(true)
        try await wait(until: { model.growthComparison?.state == "comparable" })
        XCTAssertTrue(model.currentScopeAvailable)
    }
    func testDisconnectedSampleSSDIsActuallyUnavailableAndReconnectPreservesBytes() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let state = try XCTUnwrap(context.samples), session = try XCTUnwrap(context.container)
        let file = session.appendingPathComponent("sample-ssd/verified-file")
        try Data("generated verified bytes".utf8).write(to: file)
        let expected = try FileTree.hash(file)
        try state.setVolumeConnected(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertThrowsError(try FileTree.hash(file))
        let resumed = try AppContext.resumeSamples(session: session)
        XCTAssertFalse(try XCTUnwrap(resumed.samples).volumeConnected)
        try state.setVolumeConnected(true)
        XCTAssertEqual(try FileTree.hash(file), expected)
    }
    func testActiveSessionStorageRedirectsCannotChangeSiblingFixtureConfiguration() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context), session = try XCTUnwrap(context.container), outside = root.appendingPathComponent("sibling")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let rc = outside.appendingPathComponent(".zshrc"), sentinel = Data("precious sibling fixture".utf8)
        try sentinel.write(to: rc)
        try FileManager.default.moveItem(at: context.home, to: session.appendingPathComponent("saved-home"))
        try FileManager.default.createSymbolicLink(at: context.home, withDestinationURL: outside)
        model.review = .integration; model.execute(.integration)
        XCTAssertFalse(model.busy); XCTAssertNotNil(model.errorMessage); XCTAssertNil(model.review)
        XCTAssertEqual(try Data(contentsOf: rc), sentinel)
        try FileManager.default.removeItem(at: context.home); try FileManager.default.moveItem(at: session.appendingPathComponent("saved-home"), to: context.home)
        try FileManager.default.moveItem(at: context.store.base, to: session.appendingPathComponent("saved-support"))
        try FileManager.default.createSymbolicLink(at: context.store.base, withDestinationURL: outside)
        model.preferences.language = "en"; model.savePreferences(); model.saveSettings()
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("preferences.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("settings.json").path))
        XCTAssertEqual(try Data(contentsOf: rc), sentinel)
    }
    func reviewed(_ action: ReviewAction, on model: AppModel, releaseSource: Bool = false) async throws {
        model.notice = nil; model.errorMessage = nil; model.review = action; model.releaseLocal = releaseSource
        model.execute(action)
        try await wait(until: { !model.busy && !model.inventoryRunning })
        XCTAssertNil(model.errorMessage)
        if let error = model.errorMessage { throw CacheSSDError.message(error) }
    }
    func testExplorerMoveRecoverResolveJourneyInBothLanguages() async throws {
        defer { L10n.preference = "system" }
        for language in ["pt-BR", "en"] {
            let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let session = try XCTUnwrap(context.container), model = AppModel(context: context)
            model.setLanguage(language); model.chooseFolder()
            try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
            model.search = "sample-001.txt"; try await wait(until: { !model.indexLoading })
            let item = try XCTUnwrap(model.visibleItems.first)
            let expected = try FileTree.digest(item.url, workspace: context.store.base)
            model.selectedPath = item.path; model.reviewMove(item)
            let move = try XCTUnwrap(model.review)
            try await reviewed(move, on: model)
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
            let completed = try XCTUnwrap(context.store.operations().first { $0.kind == "personalMove" })
            let destination = URL(fileURLWithPath: try XCTUnwrap(completed.destination))
            XCTAssertEqual(try FileTree.digest(destination, workspace: context.store.base), expected)
            // Emulate the durable pending checkpoint at restart. Preserve the
            // simulated Trash original and force recovery from the verified copy.
            if let path = completed.trashPath {
                try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: session.appendingPathComponent("preserved-journey-original.txt"))
            }
            var pending = completed; pending.phase = .interrupted
            try context.store.writeDurably(pending, name: "operation-\(pending.id.uuidString).json")
            let reopenedContext = try AppContext.resumeSamples(session: session), reopened = AppModel(context: reopenedContext)
            XCTAssertEqual(reopened.preferences.language, language); XCTAssertEqual(reopened.section, .explorer)
            XCTAssertEqual(reopened.pendingRecoveryCount, 1)
            let recovery = try XCTUnwrap(reopened.recoveries.first { $0.id == pending.id })
            XCTAssertTrue(recovery.canRestoreSource)
            try await reviewed(.recover(recovery), on: reopened)
            XCTAssertEqual(try FileTree.digest(item.url, workspace: context.store.base), expected)
            XCTAssertEqual(try FileTree.digest(destination, workspace: context.store.base), expected)
            // Also cover a stale checkpoint after restored source publication:
            // the visible resolve action closes the record without deleting copies.
            pending = try context.store.read(OperationJournal.self, name: "operation-\(pending.id.uuidString).json")
            pending.phase = .interrupted
            try context.store.writeDurably(pending, name: "operation-\(pending.id.uuidString).json")
            let finalContext = try AppContext.resumeSamples(session: session), finalModel = AppModel(context: finalContext)
            let toResolve = try XCTUnwrap(finalModel.recoveries.first { $0.id == pending.id })
            XCTAssertFalse(toResolve.canRestoreSource)
            try await reviewed(.resolve(toResolve), on: finalModel)
            XCTAssertEqual(finalModel.pendingRecoveryCount, 0)
            XCTAssertEqual(try FileTree.digest(item.url, workspace: context.store.base), expected)
            XCTAssertEqual(try FileTree.digest(destination, workspace: context.store.base), expected)
        }
    }
    func testFlagsWithoutDestinationsDoNotClaimCacheTransfer() throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        var settings = context.store.settings(); settings.useExternal = true; settings.shellIntegrationEnabled = true; settings.locations = [:]
        try context.store.save(settings)
        let model = AppModel(context: context); model.setLanguage("pt-BR")
        XCTAssertFalse(model.hasRegisteredCacheDestinations)
        XCTAssertEqual(model.cacheWorkflowHeadline, "Nenhum cache transferido")
        XCTAssertEqual(model.section, .explorer); XCTAssertTrue(model.choosingVolume)
        XCTAssertTrue(context.store.history().isEmpty)
    }
    func testReviewedCacheBatchSeparatesPreparedVerifiedAndAbsentSSDInBothLanguages() async throws {
        defer { L10n.preference = "system" }
        for language in ["pt-BR", "en"] {
            let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(context: context); model.setLanguage(language); model.analyzeCacheWorkflow()
            try await wait(until: { !model.cacheAnalyzing && !model.cacheEntries.isEmpty })
            let chrome = GraphicalCacheCatalog.chromeCacheID
            XCTAssertTrue(model.cacheSelectedIDs.contains(chrome)); XCTAssertTrue(model.cacheSelectedIDs.contains("npm"))
            XCTAssertTrue(model.cacheEntries.filter { ["Cursor", "Xcode", "Safari"].contains($0.title) }.allSatisfy { $0.blockedReason != nil })
            model.cacheSelectedIDs = [chrome, "npm"]; model.reviewCacheTransfer()
            let action = try XCTUnwrap(model.review)
            guard case .cacheTransfer(let plan) = action else { return XCTFail("Expected one reviewed batch") }
            XCTAssertEqual(Set(plan.eligibleEntries.map(\.id)), [chrome, "npm"])
            model.closeReviewedApplications(plan)
            XCTAssertEqual(context.samples?.events, ["close-applications"])
            try await reviewed(action, on: model)
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .configuredNeedsReopen, model.cacheTransferResults.map(\.detail).joined(separator: "; "))
            XCTAssertFalse(try XCTUnwrap(model.cacheTransferResults.first { $0.id == chrome }).sourceReleased)
            XCTAssertFalse(model.cacheTransferResults.contains { $0.state == .ssdVerified })
            XCTAssertTrue(model.selectedCacheTransferEntries.isEmpty)
            let registry = try XCTUnwrap(context.graphicalEngine().registrations().first)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(registry.sourceQuarantine).path))
            model.verifyCacheWorkflowUsage(); XCTAssertTrue(model.busy); model.cancel()
            try await wait(until: { !model.busy && !model.cacheAnalyzing })
            XCTAssertFalse(try XCTUnwrap(context.graphicalEngine().registrations().first).sourceReleased)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(registry.sourceQuarantine).path))
            model.verifyCacheWorkflowUsage(); try await wait(until: { !model.busy && !model.cacheAnalyzing })
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .ssdVerified)
            XCTAssertTrue(try XCTUnwrap(model.cacheTransferResults.first { $0.id == chrome }).sourceReleased)
            XCTAssertEqual(try context.graphicalEngine().registrations().first?.evidence?.isSimulated, true, "Generated sample evidence must remain visibly simulated in durable records")
            try XCTUnwrap(context.samples).setVolumeConnected(false)
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .localTemporary, "Absence must update without requiring another analysis")
            model.analyzeCacheWorkflow(); try await wait(until: { !model.cacheAnalyzing })
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .localTemporary)
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == "npm" }?.state, .localTemporary)
            try XCTUnwrap(context.samples).setVolumeConnected(true)
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .configuredNeedsReopen)
            try await reviewed(.graphicalResume(chrome), on: model)
            XCTAssertEqual(model.cacheTransferResults.first { $0.id == chrome }?.state, .configuredNeedsReopen)
            try await reviewed(.graphicalRestore(chrome), on: model)
            XCTAssertFalse(model.cacheRegisteredIDs.contains(chrome))
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath).path))
        }
    }
    func testRapidTreeRequestsStayBoundedAcrossQueryChanges() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.chooseFolder()
        try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let folder = try XCTUnwrap(model.currentFolder), coordinator = VolumeTreeView.Coordinator(model: model)
        coordinator.branch = VirtualTreeBranch(path: folder.path, childCount: 200_000)
        for page in 0..<1000 { coordinator.request(parent: folder.path, offset: page * 128) }
        XCTAssertLessThanOrEqual(coordinator.activeReads, 3); XCTAssertLessThanOrEqual(coordinator.pending.count, 3)
        model.search = "find-me"; coordinator.update(model)
        XCTAssertLessThanOrEqual(coordinator.activeReads, 3, "Obsolete generations still count against the global query limit")
        try await wait(until: { coordinator.activeReads == 0 && coordinator.rootLoaded })
        XCTAssertEqual(coordinator.branch.childCount, 1)
        XCTAssertLessThanOrEqual(coordinator.pages.count, 12)
    }

    func testVirtualTreeUnloadedSelectionCannotKeepPreviousTrashTarget() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.chooseFolder()
        try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let folder = try XCTUnwrap(model.currentFolder), page = try await model.treePage(parent: folder.path, offset: 0, limit: 128)
        let target = try await model.treePage(parent: folder.path, offset: 129, limit: 1)
        let expected = try XCTUnwrap(target.items.first), previous = try XCTUnwrap(page.items.first)
        let coordinator = VolumeTreeView.Coordinator(model: model), table = NSTableView()
        coordinator.branch = VirtualTreeBranch(path: folder.path, childCount: page.total)
        coordinator.pages[.init(parent: folder.path, offset: 0)] = page.items
        coordinator.table = table; table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.dataSource = coordinator; table.delegate = coordinator; table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.synchronizeSelection(); XCTAssertEqual(model.selectedItem?.path, previous.path)
        table.selectRowIndexes(IndexSet(integer: 129), byExtendingSelection: false)
        coordinator.synchronizeSelection()
        XCTAssertNil(model.selectedItem, "A loading row must never leave actions bound to the previous file")
        try await wait(until: { model.selectedItem?.path == expected.path })
        XCTAssertEqual(coordinator.selectedReference?.ordinal, 129)
        XCTAssertEqual(model.selectedItem?.fileIdentity, expected.fileIdentity)
    }
    func testExplicitResumeRebindsAStaleMountSpellingOnlyToMatchingCurrentRoot() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.preferExternalIndex = false
        try await wait(until: { !model.volumeTargets.isEmpty })
        let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { !$0.isInternal } })
        model.scanVolume(target); try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let session = model.indexedSessionID
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any])
        let oldURL = try XCTUnwrap(context.container).appendingPathComponent("previous-mount-name").absoluteString
        record["displayRoot"] = oldURL
        var roots = try XCTUnwrap(record["roots"] as? [[String: Any]]); roots[0]["url"] = oldURL; record["roots"] = roots
        let stale = try JSONDecoder().decode(VolumeScanTarget.self, from: JSONSerialization.data(withJSONObject: record))
        model.explorerTarget = stale; model.resumeExplorer()
        try await wait(until: { !model.isScanning && !model.indexLoading })
        XCTAssertNil(model.errorMessage); XCTAssertEqual(model.indexedSessionID, session)
        XCTAssertEqual(model.explorerTarget?.roots[0].url.path, target.roots[0].url.path)
    }
    func testPendingVolumeQueueIsDiscoveredAndResumedAfterAppRestart() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let initial = AppModel(context: context)
        try await wait(until: { !initial.volumeTargets.isEmpty })
        let target = try XCTUnwrap(initial.volumeTargets.first { $0.roots.contains { $0.isInternal } })
        let identifier = context.volumeIdentityProvider()
        let location = try IndexStoragePolicy.location(internalDirectory: context.store.base, externalVolume: try XCTUnwrap(initial.selectedVolume), installationID: initial.settings.installationID, targetID: target.id, filesystemType: { _ in "apfs" }, volumeIdentifier: identifier)
        let database = try location.openIndex(volumeIdentifier: identifier)
        let partial = try VolumeScanner(home: context.home, maximumEntriesPerPass: 5, volumeIdentifier: identifier).scan(target, index: database, policy: location.policy)
        XCTAssertTrue(partial.isPartial); try database.close()
        let reopened = AppModel(context: try AppContext.resumeSamples(session: XCTUnwrap(context.container)))
        try await wait(until: { reopened.resumableVolumeIDs.contains(target.id) })
        reopened.scanVolume(target, resume: true)
        try await wait(until: { reopened.report != nil && !reopened.isScanning && !reopened.indexLoading })
        XCTAssertNil(reopened.errorMessage); XCTAssertEqual(reopened.report?.id, partial.id)
        XCTAssertFalse(try XCTUnwrap(reopened.report).isPartial)
    }

    func testExternalSourceAbsenceDoesNotBecomeCompleteWhenIndexIsInternal() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.settings.selectedVolumeUUID = nil; model.saveSettings()
        try await wait(until: { model.volumeTargets.contains { $0.roots.contains { !$0.isInternal } } })
        let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { !$0.isInternal } })
        try Data("Generated source volume fixture".utf8).write(to: target.roots[0].url.appendingPathComponent("personal.txt"))
        model.scanVolume(target); try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        XCTAssertFalse(model.indexOnSSD); XCTAssertTrue(model.currentScopeAvailable)
        let previousBytes = model.report?.root.logicalBytes, session = model.indexedSessionID
        try XCTUnwrap(context.samples).setVolumeConnected(false)
        XCTAssertFalse(model.currentScopeAvailable); XCTAssertTrue(model.analysisNeedsRefresh)
        XCTAssertEqual(model.report?.root.logicalBytes, previousBytes)
        XCTAssertNil(model.selectedItem); XCTAssertTrue(model.treemapItems.isEmpty)
        try XCTUnwrap(context.samples).setVolumeConnected(true)
        model.resumeExplorer(); try await wait(until: { !model.isScanning && !model.indexLoading })
        XCTAssertTrue(model.currentScopeAvailable); XCTAssertEqual(model.indexedSessionID, session)
        model.scanVolume(target); try await wait(until: { !model.isScanning && !model.indexLoading })
        XCTAssertNotEqual(model.indexedSessionID, session, "A new scan must not be trapped in the previous resumable session")
    }

    func testCancellingEjectNeverDisconnectsTheGeneratedVolume() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context), volume = try XCTUnwrap(model.selectedVolume)
        model.review = .eject(volume); model.execute(.eject(volume)); model.cancel()
        try await wait(until: { !model.busy })
        XCTAssertTrue(try XCTUnwrap(context.samples).volumeConnected)
        XCTAssertFalse(try XCTUnwrap(context.samples).events.contains("eject"))
        XCTAssertNotNil(model.errorMessage)
    }

    func testEjectClosesExplorerIndexAndReconnectResumesThePreservedSession() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context)
        try await wait(until: { !model.volumeTargets.isEmpty })
        let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { $0.isInternal } })
        model.scanVolume(target)
        try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        let session = model.indexedSessionID, volume = try XCTUnwrap(model.selectedVolume)
        try await reviewed(.eject(volume), on: model)
        XCTAssertTrue(model.indexSuspended); XCTAssertNil(model.indexedSessionID)
        XCTAssertFalse(model.currentScopeAvailable); XCTAssertTrue(model.analysisNeedsRefresh)
        try XCTUnwrap(context.samples).setVolumeConnected(true)
        model.resumeExplorer(); try await wait(until: { !model.isScanning && !model.indexLoading })
        XCTAssertNil(model.errorMessage); XCTAssertFalse(model.indexSuspended)
        XCTAssertEqual(model.indexedSessionID, session); XCTAssertTrue(model.currentScopeAvailable)
    }

    func testNestedTreeSelectionHighlightsContainingMapBlockWithoutChangingVolume() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context)
        try await wait(until: { !model.volumeTargets.isEmpty })
        let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { $0.isInternal } })
        model.scanVolume(target)
        try await wait(until: { model.errorMessage != nil || model.report != nil && !model.isScanning && !model.indexLoading && !model.treemapItems.isEmpty })
        XCTAssertNil(model.errorMessage)
        let downloads = try XCTUnwrap(model.treemapItems.first { $0.name == "Downloads" })
        let page = try await model.treePage(parent: downloads.path, offset: 0, limit: 128)
        let nestedFile = try XCTUnwrap(page.items.first { !$0.isDirectory })
        model.selectExplorerItem(nestedFile)
        XCTAssertEqual(model.selectedItem?.path, nestedFile.path)
        XCTAssertTrue(model.treemapContainsSelection(downloads)); XCTAssertEqual(model.selectedTreemapContainer?.path, downloads.path)
        XCTAssertEqual(model.currentFolder?.path, model.report?.root.path)
        XCTAssertEqual(model.explorerTarget?.id, target.id)
        XCTAssertFalse(model.selectedInTreemapRemainder)
    }

    func testNewScanWithoutSSDUsesBoundedInternalIndexButResumeKeepsItsOriginalStorage() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context)
        try await wait(until: { !model.volumeTargets.isEmpty })
        let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { $0.isInternal } })
        model.scanVolume(target); try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        XCTAssertTrue(model.indexOnSSD)
        let session = model.indexedSessionID
        try XCTUnwrap(context.samples).setVolumeConnected(false)
        model.resumeExplorer()
        XCTAssertFalse(model.isScanning); XCTAssertNotNil(model.errorMessage); XCTAssertNil(model.indexedSessionID); XCTAssertEqual(model.report?.id, session); XCTAssertTrue(model.indexSuspended)
        model.errorMessage = nil
        model.scanVolume(target); try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
        XCTAssertFalse(model.indexOnSSD); XCTAssertNotNil(model.notice)
        let internalSession = model.indexedSessionID
        try XCTUnwrap(context.samples).setVolumeConnected(true)
        model.resumeExplorer(); try await wait(until: { !model.isScanning && !model.indexLoading })
        XCTAssertFalse(model.indexOnSSD, "Resume must keep the original index even if another destination becomes available")
        XCTAssertEqual(model.indexedSessionID, internalSession)
    }

    func testUnknownGraphicalRegistryBlocksCLITransferBeforeAnyConfigurationMutation() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let registry = context.store.base.appendingPathComponent("graphical-caches.json")
        let future = try JSONSerialization.data(withJSONObject: ["schemaVersion": 99, "installationID": context.store.settings().installationID, "active": [:]])
        try future.write(to: registry)
        let rc = context.home.appendingPathComponent(".zshrc"), rcBefore = Data("# Generated configuration that must stay unchanged\n".utf8)
        try rcBefore.write(to: rc)
        let settingsBefore = try Data(contentsOf: context.store.base.appendingPathComponent("settings.json"))
        let npm = try XCTUnwrap(CacheCatalog.find("npm", home: context.home)), cacheBefore = try FileTree.digest(npm.source)
        let model = AppModel(context: context); model.analyzeCacheWorkflow()
        try await wait(until: { !model.cacheAnalyzing && !model.cacheEntries.isEmpty })
        XCTAssertTrue(model.newCacheTransferBlocked)
        model.cacheSelectedIDs = ["npm"]; model.reviewCacheTransfer(); XCTAssertNil(model.review)
        // Revalidate at confirmation too, even if an old valid sheet survived.
        let entry = try XCTUnwrap(model.cacheEntries.first { $0.id == "npm" })
        let action = ReviewAction.cacheTransfer(CacheTransferPlan(destinationVolume: try XCTUnwrap(model.selectedVolume), entries: [entry]))
        model.review = action; model.execute(action)
        XCTAssertFalse(model.busy); XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: registry), future)
        XCTAssertEqual(try Data(contentsOf: rc), rcBefore)
        XCTAssertEqual(try Data(contentsOf: context.store.base.appendingPathComponent("settings.json")), settingsBefore)
        XCTAssertEqual(try FileTree.digest(npm.source), cacheBefore)
    }

    func testVolumeJourneyKeepsSelectedVolumeAndTrashesThroughReviewedScope() async throws {
        defer { L10n.preference = "system" }
        for language in ["pt-BR", "en"] {
            let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(context: context); model.setLanguage(language)
            try await wait(until: { !model.volumeTargets.isEmpty })
            let target = try XCTUnwrap(model.volumeTargets.first { $0.roots.contains { $0.isInternal } }, String(describing: model.volumeTargets) + " supplied " + String(describing: context.volumes()))
            let cacheVolume = model.settings.selectedVolumeUUID
            model.scanVolume(target)
            try await wait(until: { model.report != nil && !model.isScanning && !model.indexLoading })
            XCTAssertNil(model.errorMessage); XCTAssertEqual(model.explorerTarget?.id, target.id)
            XCTAssertEqual(model.settings.selectedVolumeUUID, cacheVolume); XCTAssertTrue(model.indexOnSSD)
            let rootPath = try XCTUnwrap(model.currentFolder?.path)
            let page = try await model.treePage(parent: rootPath, offset: 0, limit: 128)
            let downloads = try XCTUnwrap(page.items.first { $0.name == "Downloads" })
            model.openFolder(downloads); try await wait(until: { !model.indexLoading })
            XCTAssertEqual(model.explorerTarget?.id, target.id)
            let items = try await model.treePage(parent: downloads.path, offset: 0, limit: 128)
            let item = try XCTUnwrap(items.items.first { !$0.isDirectory })
            model.selectExplorerItem(item, ordinal: 0)
            XCTAssertEqual(model.selectedItem?.path, item.path)
            XCTAssertEqual(model.treeScrollRequest?.ordinal, 0)
            XCTAssertNil(model.trashPolicyReason(item)); model.reviewTrash(item)
            let action = try XCTUnwrap(model.review)
            guard case .volumeTrash(_, let scope) = action else { return XCTFail("Volume browsing must require a bound Trash scope") }
            XCTAssertEqual(scope.volumeUUID, target.roots.first?.identity.volumeUUID)
            try await reviewed(action, on: model)
            try await wait(until: { !model.isScanning && !model.indexLoading })
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
            let journal = try XCTUnwrap(context.store.operations().first { $0.kind == "volumeTrash" })
            XCTAssertNotNil(journal.volumeTrashScope); XCTAssertNotNil(journal.trashRelativePath)
            XCTAssertEqual(model.explorerTarget?.id, target.id)
            XCTAssertEqual(model.settings.selectedVolumeUUID, cacheVolume)
        }
    }

    func testCacheReleaseRestoreLocalDisableJourneyInBothLanguages() async throws {
        defer { L10n.preference = "system" }
        for language in ["pt-BR", "en"] {
            let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(context: context); model.setLanguage(language)
            let rc = context.home.appendingPathComponent(".zshrc"), original = "export DISKWING_SAMPLE_PROJECT=1\n"
            try Data(original.utf8).write(to: rc)
            try await reviewed(.integration, on: model)
            XCTAssertTrue(model.settings.shellIntegrationEnabled)
            model.refreshInventory(); try await wait(until: { !model.inventoryRunning })
            let tool = try XCTUnwrap(model.tools.first { $0.id == "npm" })
            let expected = try FileTree.digest(tool.source, tool: tool.id, workspace: context.store.base)
            XCTAssertTrue(model.adapterStatuses[tool.id]?.canReleaseSource == true)
            try await reviewed(.migration(tool), on: model, releaseSource: true)
            XCTAssertEqual(FileTree.measure(tool.source).logical, 0)
            let location = try XCTUnwrap(model.settings.locations[tool.id]), volume = try XCTUnwrap(model.selectedVolume)
            let copy = tool.payload(at: URL(fileURLWithPath: volume.path).appendingPathComponent(location.relativePath))
            XCTAssertEqual(try FileTree.digest(copy, tool: tool.id, workspace: context.store.base), expected)
            try await reviewed(.restore(tool), on: model)
            XCTAssertNil(model.settings.locations[tool.id])
            XCTAssertEqual(try FileTree.digest(tool.source, tool: tool.id, workspace: context.store.base), expected)
            XCTAssertEqual(try FileTree.digest(copy, tool: tool.id, workspace: context.store.base), expected)
            model.setLocalOnly()
            XCTAssertFalse(model.settings.useExternal)
            try XCTUnwrap(context.samples).setVolumeConnected(false)
            XCTAssertTrue(CacheRouter.decisions(settings: model.settings, volumes: context.volumes()).allSatisfy { $0.mode == "local" })
            try await reviewed(.disableIntegration, on: model)
            XCTAssertFalse(model.settings.shellIntegrationEnabled)
            XCTAssertFalse(model.settings.useExternal)
            let finalRC = try String(contentsOf: rc)
            XCTAssertTrue(finalRC.contains(original)); XCTAssertFalse(finalRC.contains("CacheSSD managed integration"))
            XCTAssertEqual(try FileTree.digest(tool.source, tool: tool.id, workspace: context.store.base), expected)
            XCTAssertEqual(model.preferences.language, language)
        }
    }

}

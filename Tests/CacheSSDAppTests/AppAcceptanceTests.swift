import XCTest
import Foundation
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
        XCTAssertEqual(model.section, .overview); XCTAssertEqual(model.pendingRecoveryCount, 1)
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
}

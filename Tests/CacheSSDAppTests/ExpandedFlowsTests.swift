import XCTest
import Foundation
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class ExpandedFlowsTests: XCTestCase {
    private func fixture() throws -> (URL, AppContext) {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-expanded-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, try AppContext.makeSamples(workspace: root))
    }
    private func wait(until condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition())
    }
    func testInternalStorageUsesOnlySampleHomeAndFindsApplicationCache() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        XCTAssertEqual(context.internalDataRoot(), context.home)
        let model = AppModel(context: context)
        model.scanInternalStorage()
        try await wait { model.report != nil && !model.isScanning && !model.indexLoading }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.report?.root.path, context.home.path)
        model.search = "com.example.DiskWingSample"
        try await wait { !model.indexLoading }
        XCTAssertTrue(model.visibleItems.contains { $0.name == "cache.db" })
        XCTAssertTrue(model.visibleItems.allSatisfy { context.allows($0.url) })
    }
    func testCacheTrashIsIndependentOfMoveAndRefreshesExplorerInBothLanguages() async throws {
        for language in ["pt-BR", "en"] {
            let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
            let model = AppModel(context: context); model.setLanguage(language)
            let caches = context.home.appendingPathComponent("Library/Caches")
            model.scan(caches)
            try await wait { model.report != nil && !model.isScanning && !model.indexLoading }
            let selected = try XCTUnwrap(model.visibleItems.first { $0.name == "com.example.DiskWingSample" })
            let previous = try XCTUnwrap(model.report?.id)
            XCTAssertNotNil(model.cachePolicyReason(selected))
            XCTAssertNil(model.trashPolicyReason(selected))
            XCTAssertNotNil(model.trashWarning(selected))
            model.review = .trash(selected); model.review = nil
            XCTAssertTrue(FileManager.default.fileExists(atPath: selected.path), "Cancelling review preserves content")
            model.review = .trash(selected); model.execute(.trash(selected))
            try await wait { !model.busy && !model.isScanning && !model.indexLoading }
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: selected.path))
            XCTAssertNotEqual(model.report?.id, previous)
            XCTAssertFalse(model.analysisNeedsRefresh)
            XCTAssertFalse(model.visibleItems.contains { $0.path == selected.path })
            XCTAssertTrue(model.notice.map { L10n.message($0).contains(language == "en" ? "Trash" : "Lixeira") } == true)
        }
    }
    func testAbsentCacheCanPrepareFutureWritesWithoutCreatingLocalSourceOrActivatingShell() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context)
        let npm = try XCTUnwrap(model.tools.first { $0.id == "npm" })
        try FileManager.default.removeItem(at: npm.source)
        model.refreshInventory(); try await wait { !model.inventoryRunning }
        XCTAssertTrue(model.toolSizes[npm.id]?.missing == true)
        model.review = .prepareCache(npm); model.execute(.prepareCache(npm))
        try await wait { !model.busy && !model.inventoryRunning }
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.settings.locations[npm.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: npm.source.path))
        XCTAssertFalse(model.settings.shellIntegrationEnabled)
        XCTAssertTrue(model.notice?.contains("Direcionamento pendente") == true)
        XCTAssertEqual(model.cacheStatus(npm), "Destino preparado; integração pendente")
    }
    func testFutureWriteNoticeIsFullyEnglishAndOldScriptRemainsPending() async throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context); model.setLanguage("en")
        let npm = try XCTUnwrap(model.tools.first { $0.id == "npm" })
        try FileManager.default.removeItem(at: npm.source)
        var settings = context.store.settings(); settings.shellIntegrationEnabled = true; try context.store.save(settings)
        try Data("# Legacy generated integration\n".utf8).write(to: context.store.base.appendingPathComponent("integration.zsh"))
        model.reloadRecords()
        XCTAssertFalse(model.integrationIsCurrent)
        model.review = .prepareCache(npm); model.execute(.prepareCache(npm))
        try await wait { !model.busy && !model.inventoryRunning }
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.notice?.hasPrefix("No local cache was moved or removed.") == true)
        XCTAssertTrue(model.notice?.contains("Routing pending") == true)
        XCTAssertEqual(model.cacheStatus(npm), "Destination prepared; integration pending")
    }
    func testSampleEligibilityAndUnavailableRuntimeStatusMatchProductionPolicy() throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context)
        let go = try XCTUnwrap(model.tools.first { $0.id == "go" }), ccache = try XCTUnwrap(model.tools.first { $0.id == "ccache" })
        XCTAssertFalse(context.inspect(go).canReleaseSource)
        XCTAssertEqual(context.inspect(ccache).state, "unqualified-version")
        try FileManager.default.removeItem(at: go.source)
        _ = try context.migrationEngine().prepareFutureCache(toolID: go.id)
        model.reloadRecords()
        model.adapterStatuses[go.id] = AdapterStatus(toolID: go.id, adapterVersion: 1, version: "unqualified", effectiveCachePath: nil, state: "unqualified-version", explanation: "Generated", canReleaseSource: false)
        XCTAssertEqual(model.cacheStatus(go), "Direcionamento indisponível; configuração preservada")
    }
    func testDataVolumeAliasCannotBeInferredFromMatchingNamesOrSymlink() throws {
        let (root, context) = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let fakeData = root.appendingPathComponent("data-volume")
        let guessedHome = fakeData.appendingPathComponent(String(context.home.path.dropFirst()))
        try FileManager.default.createDirectory(at: guessedHome, withIntermediateDirectories: true)
        XCTAssertNil(DataVolumePaths.alias(of: context.home, dataRoot: fakeData), "Matching paths with different inodes must not authorize an alias")
        try FileManager.default.removeItem(at: guessedHome)
        try FileManager.default.createSymbolicLink(at: guessedHome, withDestinationURL: context.home)
        XCTAssertNil(DataVolumePaths.alias(of: context.home, dataRoot: fakeData), "Symlinks cannot stand in for APFS firmlinks")
        let item = guessedHome.appendingPathComponent("Downloads/sample-001.txt")
        XCTAssertEqual(DataVolumePaths.canonicalHomeItem(item, home: context.home, dataRoot: fakeData), item)
    }
    func testNativeDataAliasWithGeneratedSharedFixtureAndPrivateIndexExclusion() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_NATIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in APFS Data alias check uses only a tiny generated /Users/Shared fixture") }
        let home = URL(fileURLWithPath: "/Users/Shared", isDirectory: true).appendingPathComponent("DiskWing-data-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        let support = home.appendingPathComponent("Library/Application Support/CacheSSD")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let source = downloads.appendingPathComponent("generated.txt")
        try Data("generated APFS alias sample".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(atPath: downloads.appendingPathComponent("generated-link").path, withDestinationPath: "generated.txt")
        try Data("private generated record".utf8).write(to: support.appendingPathComponent("keep-private"))
        let aliasHome = try XCTUnwrap(DataVolumePaths.alias(of: home))
        let aliasItem = aliasHome.appendingPathComponent("Downloads/generated.txt")
        XCTAssertEqual(DataVolumePaths.canonicalHomeItem(aliasItem, home: home), source)
        let sourceIdentity = try FileIdentity(source), aliasIdentity = try FileIdentity(aliasItem)
        XCTAssertEqual(sourceIdentity.device, aliasIdentity.device); XCTAssertEqual(sourceIdentity.inode, aliasIdentity.inode)
        let index = try ScanIndex(url: support.appendingPathComponent("index.sqlite"))
        let report = try IndexedScanner(home: home).scan(aliasHome, index: index)
        let records = try index.page(sessionID: report.id, search: "keep-private")
        XCTAssertTrue(records.items.isEmpty, "The proven Data alias of the private index parent stays excluded")
        let selected = try XCTUnwrap(try index.page(sessionID: report.id, search: "generated.txt").items.first)
        XCTAssertEqual(selected.category, .personal)
        let link = try XCTUnwrap(try index.page(sessionID: report.id, search: "generated-link").items.first)
        XCTAssertTrue(link.isSymbolicLink)
        XCTAssertEqual(report.root.fileCount, 1, "The link is recorded without counting its target again")
        XCTAssertEqual(report.root.logicalBytes, Int64(Data("generated APFS alias sample".utf8).count))
        let canonical = DataVolumePaths.canonicalHomeItem(selected.url, home: home)
        XCTAssertNil(PersonalActionPolicy.reasonPreventingTrash(canonical, home: home, storeBase: support))
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(DataVolumePaths.canonicalHomeItem(aliasItem, home: home), aliasItem, "An absent leaf cannot be granted alias authority by prefix alone")
    }
}

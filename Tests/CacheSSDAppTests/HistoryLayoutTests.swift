import XCTest
import AppKit
import SwiftUI
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class HistoryLayoutTests: XCTestCase {
    func testPendingRecoveryAndLongHistoryDoNotIncreaseMinimumWindowHeight() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-history-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldLanguage = L10n.preference
        defer { try? FileManager.default.removeItem(at: root); L10n.preference = oldLanguage }
        let context = try AppContext.makeSamples(workspace: root)
        let source = context.home.appendingPathComponent("Downloads/sample-001.txt")
        for _ in 0..<12 {
            var journal = try OperationJournal(kind: "migration", source: source, toolID: "npm")
            journal.phase = .interrupted
            try context.store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
        }
        let model = AppModel(context: context)
        model.section = .history
        XCTAssertEqual(model.recoveries.count, 12)
        for language in ["pt-BR", "en"] {
            L10n.preference = language
            for count in [0, 150] {
                model.history = (0..<count).map { _ in OperationRecord(title: "Migração de npm interrompida", detail: "A cópia não corresponde à origem. Nenhum arquivo local foi removido.", recoveryPath: source.path) }
                let host = NSHostingView(rootView: ContentView().environmentObject(model).environment(\.locale, L10n.locale).frame(minWidth: 1050, minHeight: 690))
                host.frame = NSRect(x: 0, y: 0, width: 1050, height: 690)
                host.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.height, 690, "History must scroll instead of increasing the window minimum (\(language), \(count) records)")
                XCTAssertLessThanOrEqual(host.fittingSize.width, 1050, "History must fit the minimum window width (\(language), \(count) records)")
            }
        }
    }
}

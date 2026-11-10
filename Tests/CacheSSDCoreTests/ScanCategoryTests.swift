import XCTest
import Foundation
@testable import CacheSSDCore

final class ScanCategoryTests: XCTestCase {
    func testInjectedPrivateHomeKeepsPersonalFilesSeparateFromSystemAndCaches() {
        // Synthetic paths require no access to system folders or user files.
        let home = URL(fileURLWithPath: "/private/var/generated-diskwing-session/home")
        let cacheSources = CacheCatalog.all(home: home).map { $0.source.path }
        let scanner = DiskScanner(home: home)
        let cases: [(String, ContentCategory)] = [
            (home.appendingPathComponent("Downloads/holiday.txt").path, .personal),
            (home.appendingPathComponent("Documents/notes.txt").path, .personal),
            (home.appendingPathComponent("Library/Application Support/Example/state").path, .system),
            (home.appendingPathComponent("Library/Caches/pip/artifact").path, .cache),
            (home.appendingPathComponent("Library/Developer/Example/state").path, .developer),
            (home.appendingPathComponent("Downloads/Example.app/Contents/file").path, .application),
            ("/private/var/another-generated-session/file", .system),
            ("/System/Library/generated-file", .system)
        ]
        for (path, expected) in cases {
            XCTAssertEqual(IndexedScanner.category(path, home: home, cacheSources: cacheSources), expected, path)
            XCTAssertEqual(scanner.category(URL(fileURLWithPath: path)), expected, path)
        }
    }
}

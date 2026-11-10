import XCTest
@testable import CacheSSDCore

final class TreemapTests: XCTestCase {
    func testAreasAndBoundsPreserveAggregatesWithoutOverlap() {
        let values = (1...200).map { TreemapValue(id: String($0), bytes: Int64($0 * 9)) }
        let tiles = TreemapLayout.tiles(values, width: 600, height: 400)
        XCTAssertEqual(tiles.count, values.count)
        let total = values.reduce(0.0) { $0 + Double($1.bytes) }
        for tile in tiles {
            let bytes = Double(values.first { $0.id == tile.id }!.bytes)
            XCTAssertEqual(tile.width * tile.height, bytes / total * 240_000, accuracy: 0.00001)
            XCTAssertGreaterThanOrEqual(tile.x, -0.00001); XCTAssertGreaterThanOrEqual(tile.y, -0.00001)
            XCTAssertLessThanOrEqual(tile.x + tile.width, 600.00001); XCTAssertLessThanOrEqual(tile.y + tile.height, 400.00001)
        }
        for (index, a) in tiles.enumerated() {
            for b in tiles.dropFirst(index + 1) {
                let overlapX = min(a.x+a.width, b.x+b.width) - max(a.x,b.x)
                let overlapY = min(a.y+a.height, b.y+b.height) - max(a.y,b.y)
                XCTAssertFalse(overlapX > 0.00001 && overlapY > 0.00001)
            }
        }
    }
    func testUnknownZeroAndInvalidGeometryAreNotFalseSizedBlocks() {
        XCTAssertTrue(TreemapLayout.tiles([.init(id: "unknown", bytes: 0)], width: 10, height: 10).isEmpty)
        XCTAssertTrue(TreemapLayout.tiles([.init(id: "a", bytes: 1)], width: .nan, height: 10).isEmpty)
        XCTAssertEqual(TreemapLayout.tiles([.init(id: "a", bytes: 4), .init(id: "other", bytes: 6)], width: 10, height: 10).count, 2)
    }
    func testMillionRowTreeKeepsOrdinalAndExpansionWithoutMaterializingChildren() {
        var branch = VirtualTreeBranch(path: "/", childCount: 2_000_000)
        XCTAssertEqual(branch.reference(at: 1_999_999), VirtualTreeReference(parent: "/", ordinal: 1_999_999, depth: 0))
        branch.setExpansion(parent: "/", ordinal: 1, branch: VirtualTreeBranch(path: "/folder", childCount: 50_000))
        XCTAssertEqual(branch.rowCount, 2_050_000)
        XCTAssertEqual(branch.parentReference(of: "/folder"), VirtualTreeReference(parent: "/", ordinal: 1, depth: 0))
        XCTAssertEqual(branch.reference(at: 2), VirtualTreeReference(parent: "/folder", ordinal: 0, depth: 1))
        XCTAssertEqual(branch.reference(at: 50_002), VirtualTreeReference(parent: "/", ordinal: 2, depth: 0))
        branch.setExpansion(parent: "/", ordinal: 1, branch: nil)
        XCTAssertEqual(branch.rowCount, 2_000_000)
        XCTAssertNil(branch.reference(at: 2_000_000))
    }
}

import Foundation

public struct TreemapValue: Identifiable, Sendable {
    public let id: String
    public let bytes: Int64
    public init(id: String, bytes: Int64) { self.id = id; self.bytes = bytes }
}

public struct TreemapTile: Identifiable, Sendable {
    public let id: String
    public let x: Double, y: Double, width: Double, height: Double
}

/// Squarified layout adapted from DiskPilot (MIT), pinned in THIRD_PARTY_NOTICES.
/// The input contains complete SQL aggregates, not a truncated directory tree.
public enum TreemapLayout {
    public static func tiles(_ values: [TreemapValue], width: Double, height: Double) -> [TreemapTile] {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
        let sorted = values.filter { $0.bytes > 0 }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        let total = sorted.reduce(0.0) { $0 + Double($1.bytes) }
        guard total > 0, total.isFinite else { return [] }
        let entries = sorted.map { ($0.id, Double($0.bytes) / total * width * height) }
        var cursor = 0, row: [(String, Double)] = [], output: [TreemapTile] = []
        var x = 0.0, y = 0.0, w = width, h = height
        func worst(_ items: [(String, Double)], side: Double) -> Double {
            guard side > 0, !items.isEmpty else { return .infinity }
            let length = items.reduce(0) { $0 + $1.1 } / side
            guard length > 0 else { return .infinity }
            return items.reduce(0) { result, item in
                let short = item.1 / length
                return max(result, max(length / short, short / length))
            }
        }
        func place(_ items: [(String, Double)]) {
            let area = items.reduce(0) { $0 + $1.1 }
            guard area > 0, w > 0, h > 0 else { return }
            if w >= h {
                let rowWidth = min(w, area / h)
                var offset = y
                for item in items {
                    let rowHeight = h * item.1 / area
                    output.append(TreemapTile(id: item.0, x: x, y: offset, width: rowWidth, height: rowHeight))
                    offset += rowHeight
                }
                x += rowWidth; w = max(0, w - rowWidth)
            } else {
                let rowHeight = min(h, area / w)
                var offset = x
                for item in items {
                    let rowWidth = w * item.1 / area
                    output.append(TreemapTile(id: item.0, x: offset, y: y, width: rowWidth, height: rowHeight))
                    offset += rowWidth
                }
                y += rowHeight; h = max(0, h - rowHeight)
            }
        }
        while cursor < entries.count {
            let next = row + [entries[cursor]]
            if row.isEmpty || worst(next, side: min(w, h)) <= worst(row, side: min(w, h)) {
                row = next; cursor += 1
            } else { place(row); row.removeAll(keepingCapacity: true) }
        }
        place(row)
        return output
    }
}

/// Stores expanded branches only. A directory with millions of collapsed
/// children costs one count, and rows are fetched from SQL on demand.
public struct VirtualTreeBranch: Sendable {
    public let path: String
    public var childCount: Int
    public var expanded: [Int: VirtualTreeBranch] = [:]
    public init(path: String, childCount: Int) { self.path = path; self.childCount = max(0, childCount) }
    public var rowCount: Int { expanded.values.reduce(childCount) { $0 + $1.rowCount } }
    public func reference(at row: Int, depth: Int = 0) -> VirtualTreeReference? {
        guard row >= 0, row < rowCount else { return nil }
        var logical = row, previous = 0
        for ordinal in expanded.keys.sorted() {
            guard ordinal >= previous, ordinal < childCount, let branch = expanded[ordinal] else { continue }
            let direct = ordinal - previous + 1
            if logical < direct { return VirtualTreeReference(parent: path, ordinal: previous + logical, depth: depth) }
            logical -= direct
            if logical < branch.rowCount { return branch.reference(at: logical, depth: depth + 1) }
            logical -= branch.rowCount; previous = ordinal + 1
        }
        return VirtualTreeReference(parent: path, ordinal: previous + logical, depth: depth)
    }
    public mutating func setExpansion(parent: String, ordinal: Int, branch: VirtualTreeBranch?) {
        if path == parent { expanded[ordinal] = branch; return }
        for key in expanded.keys {
            expanded[key]?.setExpansion(parent: parent, ordinal: ordinal, branch: branch)
        }
    }
    public func isExpanded(parent: String, ordinal: Int) -> Bool {
        if parent == path { return expanded[ordinal] != nil }
        return expanded.values.contains { $0.isExpanded(parent: parent, ordinal: ordinal) }
    }
    public func rowIndex(parent: String, ordinal: Int) -> Int? {
        if path == parent {
            guard ordinal >= 0, ordinal < childCount else { return nil }
            return ordinal + expanded.filter { $0.key < ordinal }.values.reduce(0) { $0 + $1.rowCount }
        }
        var extra = 0
        for key in expanded.keys.sorted() {
            guard let branch = expanded[key] else { continue }
            if let nested = branch.rowIndex(parent: parent, ordinal: ordinal) { return key + extra + 1 + nested }
            extra += branch.rowCount
        }
        return nil
    }
}

public struct VirtualTreeReference: Equatable, Sendable {
    public let parent: String
    public let ordinal: Int
    public let depth: Int
}

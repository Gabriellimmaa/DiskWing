import Foundation
import Darwin

enum GraphicalCacheProcessProbe {
    static func accesses(pids: Set<Int>, destination: URL, source: URL) -> (read: Set<Int>, write: Set<Int>) {
        guard let snapshot = try? GraphicalProcessFiles.snapshot(pids: pids, destination: destination, managedSource: source) else { return ([], []) }
        return (snapshot.readers, snapshot.writers)
    }
}

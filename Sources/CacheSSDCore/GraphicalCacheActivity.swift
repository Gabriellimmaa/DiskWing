import Foundation
import AppKit
import CryptoKit
import Darwin

public enum GraphicalCacheActivity {
    /// Metadata only, commutative across directory enumeration order, bounded by
    /// the same entry/depth limits as verified transfer. It never reads cache data.
    public static func fingerprint(_ root: URL) throws -> String {
        var rootInfo = stat()
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().path,
              lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
              rootInfo.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
        var complete = true
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in complete = false; return false }) else { throw failure() }
        var combined = [UInt8](repeating: 0, count: 32), count = 0
        while let item = enumerator.nextObject() as? URL {
            count += 1; guard count <= 1_000_000 else { throw failure() }
            let relative = String(item.path.dropFirst(root.path.count + 1))
            guard relative.split(separator: "/").count <= 80 else { throw failure() }
            var metadata = stat()
            guard lstat(item.path, &metadata) == 0, metadata.st_dev == rootInfo.st_dev,
                  metadata.st_flags & UInt32(SF_DATALESS) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG || metadata.st_mode & S_IFMT == S_IFDIR else { throw failure() }
            let key = "\(relative)\0\(metadata.st_ino)\0\(metadata.st_size)\0\(metadata.st_mtimespec.tv_sec).\(metadata.st_mtimespec.tv_nsec)"
            let digest = Array(SHA256.hash(data: Data(key.utf8)))
            for index in combined.indices { combined[index] ^= digest[index] }
        }
        guard complete else { throw failure() }
        return String(count) + ":" + combined.map { String(format: "%02x", $0) }.joined()
    }

    /// A link or a touched marker cannot satisfy this observer. The qualified
    /// application's processes need regular cache files open for reading/writing,
    /// and the cache metadata must change after activation. Native HTTP reuse is
    /// established separately by the version-bound generated application test.
    static func observe(_ candidate: GraphicalCacheCandidate, _ destination: URL, _ baseline: String) throws -> GraphicalCacheUsageEvidence? {
        guard candidate.id == GraphicalCacheCatalog.chromeCacheID, let application = candidate.applicationURL,
              let version = candidate.applicationVersion,
              let current = try? fingerprint(destination), current != baseline else { return nil }
        let applicationPath = application.resolvingSymlinksInPath().path + "/"
        let processes = try CommandRunner.run(URL(fileURLWithPath: "/bin/ps"), ["-ww", "-axo", "pid=,comm="], timeout: 10, maxOutputBytes: 8_388_608)
        guard processes.status == 0, !processes.truncated else { return nil }
        var selected = Set<Int>()
        for line in processes.output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]), pid > 0, pid != getpid(), String(parts[1]).hasPrefix(applicationPath) else { continue }
            selected.insert(pid)
        }
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == candidate.applicationID && !app.isTerminated {
            selected.insert(Int(app.processIdentifier))
        }
        guard !selected.isEmpty else { return nil }
        let result = try CommandRunner.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-n", "-P", "-a", "-p", selected.sorted().map(String.init).joined(separator: ","), "-Fpcfatn"], timeout: 20, maxOutputBytes: 8_388_608)
        guard result.status == 0 || result.status == 1, !result.truncated else { return nil }
        let observed = accesses(result.output, destination: destination, permittedPIDs: selected)
        guard observed.read, observed.write else { return nil }
        return GraphicalCacheUsageEvidence(applicationVersion: version, processIDs: observed.pids.sorted(),
                                            observedReadAccess: true, observedWriteAccess: true, metadataFingerprint: current)
    }

    static func accesses(_ output: String, destination: URL, permittedPIDs: Set<Int>) -> (read: Bool, write: Bool, pids: Set<Int>) {
        var pid = 0, access = "", type = "", name = "", read = false, write = false, seen = Set<Int>()
        let root = destination.standardizedFileURL.path + "/"
        func consume() {
            guard permittedPIDs.contains(pid), type == "REG", name.hasPrefix(root),
                  !name.hasSuffix(" (deleted)") else { return }
            if access == "r" || access == "u" { read = true; seen.insert(pid) }
            if access == "w" || access == "u" { write = true; seen.insert(pid) }
        }
        for line in output.split(separator: "\n") {
            guard let prefix = line.first else { continue }; let value = String(line.dropFirst())
            if prefix == "p" { consume(); pid = Int(value) ?? 0; access = ""; type = ""; name = "" }
            else if prefix == "f" { consume(); access = ""; type = ""; name = "" }
            else if prefix == "a" { access = value }
            else if prefix == "t" { type = value }
            else if prefix == "n" { name = value }
        }
        consume(); return (read, write, seen)
    }
    private static func failure() -> Error { CacheSSDError.message("Ainda não foi possível medir a atividade deste cache com segurança.") }
}

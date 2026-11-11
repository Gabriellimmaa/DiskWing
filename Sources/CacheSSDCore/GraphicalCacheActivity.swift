import Foundation
import AppKit
import CryptoKit
import Darwin
import Security

public enum GraphicalCacheActivity {
    /// Metadata only, commutative across directory enumeration order, bounded by
    /// the same entry/depth limits as verified transfer. It never reads cache data.
    public static func fingerprint(_ root: URL, cancellation: CancellationFlag = CancellationFlag()) throws -> String {
        guard !cancellation.isCancelled else { throw CacheSSDError.message("Operação cancelada; origem preservada.") }
        var rootInfo = stat()
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().path,
              lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
              rootInfo.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
        var complete = true
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in complete = false; return false }) else { throw failure() }
        var combined = [UInt8](repeating: 0, count: 32), count = 0
        var finished = false
        while !finished {
            try autoreleasepool {
                for _ in 0..<128 {
                    guard let item = enumerator.nextObject() as? URL else { finished = true; break }
                    if count % 128 == 0, cancellation.isCancelled { throw CacheSSDError.message("Operação cancelada; origem preservada.") }
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
            }
        }
        guard complete else { throw failure() }
        return String(count) + ":" + combined.map { String(format: "%02x", $0) }.joined()
    }

    /// A link or a touched marker cannot satisfy this observer. The qualified
    /// application's processes need regular cache files open for reading/writing,
    /// and the cache metadata must change after activation. Native HTTP reuse is
    /// established separately by the version-bound generated application test.
    static func observe(_ candidate: GraphicalCacheCandidate, _ destination: URL, _ baseline: String,
                        cancellation: CancellationFlag = CancellationFlag()) throws -> GraphicalCacheUsageEvidence? {
        guard candidate.id == GraphicalCacheCatalog.chromeCacheID, let application = candidate.applicationURL,
              let version = candidate.applicationVersion else { return nil }
        let applicationPath = application.resolvingSymlinksInPath().path + "/"
        let deadline = DispatchTime.now().uptimeNanoseconds + 8_000_000_000
        var readers = [Int: GraphicalProcessIdentity](), writers = [Int: GraphicalProcessIdentity]()
        var selected = Set<Int>(), nextRefresh: UInt64 = 0
        while DispatchTime.now().uptimeNanoseconds < deadline {
            guard !cancellation.isCancelled else { throw CacheSSDError.message("Operação cancelada; origem preservada.") }
            if DispatchTime.now().uptimeNanoseconds >= nextRefresh {
                let pids = try GraphicalProcessFiles.processIDs(cancellation: cancellation)
                selected = Set(pids.filter { pid in
                    pid != getpid() && GraphicalProcessFiles.executablePath(pid: pid)?.hasPrefix(applicationPath) == true
                })
                nextRefresh = DispatchTime.now().uptimeNanoseconds + 500_000_000
            }
            let sample = try GraphicalProcessFiles.snapshot(pids: selected, destination: destination, managedSource: candidate.sourceURL, cancellation: cancellation)
            for file in sample.files {
                if file.readable { readers[file.process.pid] = file.process }
                if file.writable { writers[file.process.pid] = file.process }
            }
            if !readers.isEmpty && !writers.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        func valid(_ entry: (key: Int, value: GraphicalProcessIdentity)) -> Bool {
            GraphicalProcessFiles.isCurrent(entry.value) && signedVersion(pid: entry.key) == version &&
            belongsToApplication(pid: entry.key, path: applicationPath) && GraphicalProcessFiles.isCurrent(entry.value)
        }
        let validReaders = Set(readers.filter(valid).keys)
        let validWriters = Set(writers.filter(valid).keys)
        guard !validReaders.isEmpty, !validWriters.isEmpty,
              let current = try? fingerprint(destination, cancellation: cancellation), current != baseline else {
            if ProcessInfo.processInfo.environment["DISKWING_RUN_GRAPHICAL_NATIVE_TESTS"] == "1" { print("Generated process observation: selected=\(selected.count), readers=\(readers.count), writers=\(writers.count), qualifiedReaders=\(validReaders.count), qualifiedWriters=\(validWriters.count)") }
            return nil
        }
        return GraphicalCacheUsageEvidence(applicationVersion: version, processIDs: validReaders.union(validWriters).sorted(),
            observedReadAccess: true, observedWriteAccess: true, metadataFingerprint: current)
    }
    private static func belongsToApplication(pid: Int, path: String) -> Bool {
        var code: SecCode?, staticCode: SecStaticCode?, url: CFURL?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code, SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode, SecCodeCopyPath(staticCode, SecCSFlags(rawValue: 0), &url) == errSecSuccess,
              let url else { return false }
        let actual = (url as URL).resolvingSymlinksInPath().path
        return actual == String(path.dropLast()) || actual.hasPrefix(path)
    }
    private static func signedVersion(pid: Int) -> String? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code, let requirement = GraphicalCacheCatalog.chromeProcessRequirement(),
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any], let plist = values[kSecCodeInfoPList as String] as? [String: Any] else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    static func accesses(_ output: String, destination: URL, permittedPIDs: Set<Int>, source: URL? = nil) -> (read: Bool, write: Bool, pids: Set<Int>) {
        var pid = 0, access = "", type = "", name = "", read = false, write = false, seen = Set<Int>()
        let root = destination.standardizedFileURL.path + "/"
        func consume() {
            let direct = name.hasPrefix(root)
            let managedSpelling = source.map { name.hasPrefix($0.path + "/") && Paths.contains(Paths.physicalURL(URL(fileURLWithPath: name)), in: destination) } ?? false
            guard permittedPIDs.contains(pid), type == "REG", direct || managedSpelling,
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

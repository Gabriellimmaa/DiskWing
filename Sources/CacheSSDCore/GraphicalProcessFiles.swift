import Foundation
import Darwin

public struct GraphicalProcessIdentity: Equatable, Sendable {
    public let pid: Int
    public let startedSeconds: UInt64
    public let startedMicroseconds: UInt64
}

public struct GraphicalProcessOpenFile: Sendable {
    public let process: GraphicalProcessIdentity
    public let descriptor: Int32
    public let fileIdentity: FileIdentity
    public let relativePath: String
    public let readable: Bool
    public let writable: Bool
}

public struct GraphicalProcessFileSnapshot: Sendable {
    public let files: [GraphicalProcessOpenFile]
    public let queriedDescriptors: Int
    public let limitReached: Bool
    public var readers: Set<Int> { Set(files.filter(\.readable).map { $0.process.pid }) }
    public var writers: Set<Int> { Set(files.filter(\.writable).map { $0.process.pid }) }
}

/// Public libproc metadata only. This snapshots live descriptors, never reads
/// payloads or infers an open descriptor from a mapping, marker or application
/// name. The caller still verifies the selected process's code identity.
public enum GraphicalProcessFiles {
    public struct Limits: Sendable {
        public let maximumPIDs: Int
        public let maximumDescriptorsPerPID: Int
        public let maximumTotalDescriptors: Int
        public let maximumResults: Int
        public let durationSeconds: Double
        public init(maximumPIDs: Int = 256, maximumDescriptorsPerPID: Int = 16_384,
                    maximumTotalDescriptors: Int = 65_536, maximumResults: Int = 256, durationSeconds: Double = 0.25) {
            self.maximumPIDs = max(0, min(256, maximumPIDs))
            self.maximumDescriptorsPerPID = max(0, min(65_536, maximumDescriptorsPerPID))
            self.maximumTotalDescriptors = max(0, min(131_072, maximumTotalDescriptors))
            self.maximumResults = max(0, min(1024, maximumResults))
            self.durationSeconds = durationSeconds.isFinite ? max(0, min(2, durationSeconds)) : 0
        }
    }
    public static func processIdentity(pid: Int) -> GraphicalProcessIdentity? {
        guard pid > 0, pid <= Int(Int32.max) else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return GraphicalProcessIdentity(pid: pid, startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec)
    }
    public static func isCurrent(_ process: GraphicalProcessIdentity) -> Bool { processIdentity(pid: process.pid) == process }

    public static func snapshot(pids: Set<Int>, destination: URL, managedSource: URL? = nil,
                                cancellation: CancellationFlag = CancellationFlag(), limits: Limits = Limits()) throws -> GraphicalProcessFileSnapshot {
        if cancellation.isCancelled { throw cancelled() }
        guard pids.count <= limits.maximumPIDs, limits.maximumDescriptorsPerPID > 0, limits.maximumTotalDescriptors > 0, limits.maximumResults > 0, limits.durationSeconds > 0 else {
            return GraphicalProcessFileSnapshot(files: [], queriedDescriptors: 0, limitReached: true)
        }
        let rootFD = directory(destination)
        guard rootFD >= 0 else { throw unavailable() }; defer { close(rootFD) }
        var root = stat()
        guard fstat(rootFD, &root) == 0, let rootPath = descriptorPath(rootFD) else { throw unavailable() }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        var sourcePrefix: String?
        if let source = managedSource, source.isFileURL {
            let parent = directory(source.deletingLastPathComponent())
            if parent >= 0 {
                defer { close(parent) }
                // Follow only the caller's managed leaf, then prove that it
                // resolves to the exact destination directory already opened.
                let alias = openat(parent, source.lastPathComponent, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                if alias >= 0 {
                    defer { close(alias) }
                    var metadata = stat()
                    if fstat(alias, &metadata) == 0, metadata.st_dev == root.st_dev, metadata.st_ino == root.st_ino { sourcePrefix = source.path + "/" }
                }
            }
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let duration = UInt64(limits.durationSeconds * 1_000_000_000)
        func expired() -> Bool { DispatchTime.now().uptimeNanoseconds &- start >= duration }
        var output: [GraphicalProcessOpenFile] = [], total = 0, bounded = false
        for pid in pids.sorted() {
            if cancellation.isCancelled { throw cancelled() }
            if expired() || total >= limits.maximumTotalDescriptors || output.count >= limits.maximumResults { bounded = true; break }
            guard let process = processIdentity(pid: pid) else { continue }
            let needed = proc_pidinfo(Int32(pid), PROC_PIDLISTFDS, 0, nil, 0)
            let stride = MemoryLayout<proc_fdinfo>.stride
            guard needed > 0, needed <= 4_194_304 else { if needed > 0 { bounded = true }; continue }
            let capacity = min(limits.maximumDescriptorsPerPID, Int(needed) / stride + 32)
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
            let received = descriptors.withUnsafeMutableBytes { proc_pidinfo(Int32(pid), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            guard received > 0, received % Int32(stride) == 0 else { continue }
            if Int(received) >= capacity * stride { bounded = true }
            var current: [GraphicalProcessOpenFile] = []
            for entry in descriptors.prefix(min(capacity, Int(received) / stride)) {
                if cancellation.isCancelled { throw cancelled() }
                if expired() || total >= limits.maximumTotalDescriptors || output.count + current.count >= limits.maximumResults { bounded = true; break }
                total += 1
                guard entry.proc_fdtype == PROX_FDTYPE_VNODE else { continue }
                var info = vnode_fdinfowithpath()
                guard proc_pidfdinfo(Int32(pid), entry.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout<vnode_fdinfowithpath>.size)) == MemoryLayout<vnode_fdinfowithpath>.size else { continue }
                let vnode = info.pvip.vip_vi.vi_stat
                guard vnode.vst_mode & UInt16(S_IFMT) == UInt16(S_IFREG), vnode.vst_nlink > 0 else { continue }
                var tuple = info.pvip.vip_path
                guard let path = withUnsafeBytes(of: &tuple, { bytes -> String? in
                    let view = bytes.bindMemory(to: UInt8.self)
                    guard let end = view.firstIndex(of: 0) else { return nil }
                    return String(bytes: view[..<end], encoding: .utf8)
                }) else { continue }
                let relative: String
                if path.hasPrefix(prefix) { relative = String(path.dropFirst(prefix.count)) }
                else if let sourcePrefix, path.hasPrefix(sourcePrefix) { relative = String(path.dropFirst(sourcePrefix.count)) }
                else { continue }
                let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }),
                      currentFile(parts, under: rootFD, rootDevice: root.st_dev, matches: vnode) else { continue }
                // proc_fileinfo uses the kernel FREAD/FWRITE bits. O_RDONLY is
                // zero and is not a substitute for this access information.
                let readable = info.pfi.fi_openflags & UInt32(FREAD) != 0
                let writable = info.pfi.fi_openflags & UInt32(FWRITE) != 0
                guard readable || writable else { continue }
                let identity = FileIdentity(device: Int64(Int32(bitPattern: vnode.vst_dev)), inode: vnode.vst_ino, size: vnode.vst_size,
                    modifiedNanoseconds: vnode.vst_mtime &* 1_000_000_000 &+ vnode.vst_mtimensec)
                current.append(GraphicalProcessOpenFile(process: process, descriptor: entry.proc_fd, fileIdentity: identity, relativePath: relative, readable: readable, writable: writable))
            }
            // Discard an exited/reused PID rather than attributing an earlier
            // descriptor to a newly signed process with the same number.
            if isCurrent(process) { output.append(contentsOf: current) }
        }
        var after = stat(), pathIdentity = stat()
        guard fstat(rootFD, &after) == 0, lstat(destination.path, &pathIdentity) == 0,
              after.st_dev == root.st_dev, after.st_ino == root.st_ino,
              pathIdentity.st_dev == root.st_dev, pathIdentity.st_ino == root.st_ino, pathIdentity.st_mode & S_IFMT == S_IFDIR else { throw unavailable() }
        return GraphicalProcessFileSnapshot(files: output, queriedDescriptors: total, limitReached: bounded)
    }

    private static func directory(_ url: URL) -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { return -1 }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return -1 }
        for part in url.pathComponents.dropFirst() {
            guard part != ".", part != "..", !part.contains("\0") else { close(descriptor); return -1 }
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { return -1 }; descriptor = next
        }
        return descriptor
    }
    private static func descriptorPath(_ descriptor: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &path) == 0 else { return nil }
        return String(cString: path)
    }
    private static func currentFile(_ parts: [String], under root: Int32, rootDevice: dev_t, matches expected: vinfo_stat) -> Bool {
        var descriptor = dup(root)
        guard descriptor >= 0 else { return false }; defer { close(descriptor) }
        for part in parts.dropLast() {
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return false }
            close(descriptor); descriptor = next
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_dev == rootDevice else { return false }
        }
        var metadata = stat()
        guard let leaf = parts.last, fstatat(descriptor, leaf, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_dev == rootDevice,
              UInt32(bitPattern: metadata.st_dev) == expected.vst_dev, UInt64(metadata.st_ino) == expected.vst_ino else { return false }
        return true
    }
    private static func cancelled() -> Error { CacheSSDError.message("Operação cancelada; origem preservada.") }
    private static func unavailable() -> Error { CacheSSDError.message("Ainda não foi possível observar os arquivos deste cache com segurança.") }
}

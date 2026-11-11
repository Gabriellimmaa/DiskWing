import Foundation
import Darwin

enum GraphicalCacheFiles {
    private static func failure() -> Error { CacheSSDError.message("O caminho do cache mudou ou não permite uma operação segura. Os dados foram preservados.") }
    static func openLeaf(_ components: [String], under root: Int32, device: dev_t) throws -> Int32 {
        guard components.count <= 80, components.allSatisfy(Paths.safeComponent) else { throw failure() }
        var descriptor = dup(root); guard descriptor >= 0 else { throw failure() }
        do {
            for (offset, component) in components.enumerated() {
                let flags = O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (offset + 1 == components.count ? 0 : O_DIRECTORY)
                let next = openat(descriptor, component, flags)
                guard next >= 0 else { throw failure() }
                close(descriptor); descriptor = next
                var metadata = stat()
                guard fstat(descriptor, &metadata) == 0, metadata.st_dev == device,
                      metadata.st_flags & UInt32(SF_DATALESS) == 0,
                      metadata.st_mode & S_IFMT == S_IFREG || metadata.st_mode & S_IFMT == S_IFDIR else { throw failure() }
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }
    static func openBoundDirectory(_ directory: URL, under anchor: URL, expected: GraphicalCacheDirectoryIdentity) throws -> Int32 {
        let parent = try openParent(of: directory, under: anchor, create: false); defer { close(parent) }
        let descriptor = openat(parent, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        var metadata = stat()
        let birth = fstat(descriptor, &metadata) == 0 ? Int64(metadata.st_birthtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_birthtimespec.tv_nsec) : -1
        guard metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_flags & UInt32(SF_DATALESS) == 0,
              Int64(metadata.st_dev) == expected.device, UInt64(metadata.st_ino) == expected.inode,
              birth == expected.birthNanoseconds, metadata.st_uid == expected.owner else { close(descriptor); throw failure() }
        return descriptor
    }
    static func createDirectory(_ directory: URL, under anchor: URL) throws {
        let descriptor = try openDirectory(directory, under: anchor, create: true)
        close(descriptor)
    }
    static func openParent(of item: URL, under anchor: URL, create: Bool) throws -> Int32 {
        try openDirectory(item.deletingLastPathComponent(), under: anchor, create: create)
    }
    private static func openDirectory(_ directory: URL, under anchor: URL, create: Bool) throws -> Int32 {
        let anchorPath = normalizedSystemPath(anchor.path), directoryPath = normalizedSystemPath(directory.path)
        guard directoryPath == anchorPath || directoryPath.hasPrefix(anchorPath + "/"), noSymlinkComponents(anchorPath) else { throw failure() }
        let relative = String(directoryPath.dropFirst(anchorPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = relative.isEmpty ? [] : relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(Paths.safeComponent) else { throw failure() }
        var descriptor = open(anchor.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { close(descriptor); throw failure() }
        let device = metadata.st_dev
        do {
            for part in parts {
                if create, mkdirat(descriptor, part, 0o700) != 0, errno != EEXIST { throw failure() }
                let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw failure() }
                close(descriptor); descriptor = next
                guard fstat(descriptor, &metadata) == 0, metadata.st_dev == device else { throw failure() }
            }
            try assertParent(descriptor, matches: directory)
            return descriptor
        } catch { close(descriptor); throw error }
    }
    static func assertParent(_ descriptor: Int32, matches path: URL) throws {
        var opened = stat(), current = stat()
        guard noSymlinkComponents(normalizedSystemPath(path.path)),
              fstat(descriptor, &opened) == 0, lstat(path.path, &current) == 0,
              opened.st_dev == current.st_dev, opened.st_ino == current.st_ino,
              current.st_mode & S_IFMT == S_IFDIR else { throw failure() }
    }
    /// Only the system-owned /var and /tmp aliases are normalized, after stat
    /// proves they name the same object as /private. User redirects stay visible
    /// to the component-by-component O_NOFOLLOW walk.
    static func normalizedSystemPath(_ path: String) -> String {
        for name in ["var", "tmp"] where path == "/" + name || path.hasPrefix("/" + name + "/") {
            var alias = stat(), target = stat(), link = stat()
            if lstat("/" + name, &link) == 0, link.st_mode & S_IFMT == S_IFLNK, link.st_uid == 0,
               stat("/" + name, &alias) == 0, stat("/private/" + name, &target) == 0,
               alias.st_dev == target.st_dev, alias.st_ino == target.st_ino { return "/private" + path }
        }
        return path
    }
    private static func noSymlinkComponents(_ path: String) -> Bool {
        var current = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." || component == ".." { return false }
            current += "/" + component
            var metadata = stat()
            if lstat(current, &metadata) != 0 { return errno == ENOENT }
            if metadata.st_mode & S_IFMT == S_IFLNK { return false }
        }
        return true
    }
    static func removeDirectory(_ name: String, parent: Int32, expectedIdentity: FileIdentity, cancellation: CancellationFlag) throws {
        guard Paths.safeComponent(name) else { throw failure() }
        let directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw failure() }
        defer { close(directory) }
        var metadata = stat()
        guard fstat(directory, &metadata) == 0, metadata.st_uid == getuid(),
              Int64(metadata.st_dev) == expectedIdentity.device, UInt64(metadata.st_ino) == expectedIdentity.inode,
              expectedIdentity.size == nil || expectedIdentity.size == Int64(metadata.st_size),
              expectedIdentity.modifiedNanoseconds == nil || expectedIdentity.modifiedNanoseconds == Int64(metadata.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_mtimespec.tv_nsec) else { throw failure() }
        var count = 0
        try removeContents(directory, device: metadata.st_dev, depth: 0, count: &count, cancellation: cancellation)
        guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw failure() }
    }
    private static func removeContents(_ descriptor: Int32, device: dev_t, depth: Int, count: inout Int, cancellation: CancellationFlag) throws {
        var root = stat()
        guard depth <= 80, fstat(descriptor, &root) == 0, root.st_dev == device,
              root.st_mode & S_IFMT == S_IFDIR, root.st_flags & UInt32(SF_DATALESS) == 0,
              let stream = fdopendir(dup(descriptor)) else { throw failure() }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else { guard errno == 0 else { throw failure() }; break }
            guard !cancellation.isCancelled else { throw CacheSSDError.message("Liberação cancelada; a cópia no SSD e a recuperação foram preservadas.") }
            var tuple = entry.pointee.d_name
            let name = withUnsafeBytes(of: &tuple) { bytes in String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            if name == "." || name == ".." { continue }
            count += 1; guard count <= 1_000_000, Paths.safeComponent(name) else { throw failure() }
            var metadata = stat()
            guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                  metadata.st_dev == device, metadata.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
            if metadata.st_mode & S_IFMT == S_IFDIR {
                let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw failure() }
                do { try removeContents(child, device: device, depth: depth + 1, count: &count, cancellation: cancellation) }
                catch { close(child); throw error }
                close(child)
                guard unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else { throw failure() }
            } else {
                guard metadata.st_mode & S_IFMT == S_IFREG || metadata.st_mode & S_IFMT == S_IFLNK else { throw failure() }
                guard unlinkat(descriptor, name, 0) == 0 else { throw failure() }
            }
        }
    }
}

import Foundation
import Darwin

enum GraphicalCacheFiles {
    private static func failure() -> Error { CacheSSDError.message("O caminho do cache mudou ou não permite uma operação segura. Os dados foram preservados.") }
    static func createDirectory(_ directory: URL, under anchor: URL) throws {
        let descriptor = try openDirectory(directory, under: anchor, create: true)
        close(descriptor)
    }
    static func openParent(of item: URL, under anchor: URL, create: Bool) throws -> Int32 {
        try openDirectory(item.deletingLastPathComponent(), under: anchor, create: create)
    }
    private static func openDirectory(_ directory: URL, under anchor: URL, create: Bool) throws -> Int32 {
        guard Paths.contains(directory, in: anchor), anchor.standardizedFileURL.path == anchor.resolvingSymlinksInPath().path else { throw failure() }
        let relative = String(directory.standardizedFileURL.path.dropFirst(anchor.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
        guard path.standardizedFileURL.path == path.resolvingSymlinksInPath().path,
              fstat(descriptor, &opened) == 0, lstat(path.path, &current) == 0,
              opened.st_dev == current.st_dev, opened.st_ino == current.st_ino,
              current.st_mode & S_IFMT == S_IFDIR else { throw failure() }
    }
    static func removeDirectory(_ name: String, parent: Int32) throws {
        guard Paths.safeComponent(name) else { throw failure() }
        let directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw failure() }
        defer { close(directory) }
        var metadata = stat()
        guard fstat(directory, &metadata) == 0, metadata.st_uid == getuid() else { throw failure() }
        var count = 0
        try removeContents(directory, device: metadata.st_dev, depth: 0, count: &count)
        guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw failure() }
    }
    private static func removeContents(_ descriptor: Int32, device: dev_t, depth: Int, count: inout Int) throws {
        guard depth <= 80, let stream = fdopendir(dup(descriptor)) else { throw failure() }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
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
                do { try removeContents(child, device: device, depth: depth + 1, count: &count) }
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

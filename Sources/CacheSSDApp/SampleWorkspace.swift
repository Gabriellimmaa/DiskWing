import Foundation
import Darwin
import CacheSSDCore

/// Filesystem work is independent of AppKit and runs off the launch/main thread.
struct PreparedSampleSession: Sendable {
    let root: URL
    let home: URL
    let support: URL
    let helper: URL
    let connected: Bool
    let identity: FileIdentity
    fileprivate init(root: URL, home: URL, support: URL, helper: URL, connected: Bool, identity: FileIdentity) {
        self.root = root; self.home = home; self.support = support; self.helper = helper; self.connected = connected; self.identity = identity
    }
}

enum SampleWorkspace {
    static func failure() -> Error { CacheSSDError.message("Não foi possível iniciar o modo de amostras. Escolha uma pasta existente, sem links e com espaço disponível.") }
    static func validSupportEntry(_ info: stat) -> Bool {
        let kind = info.st_mode & S_IFMT
        return (kind == S_IFDIR || kind == S_IFREG) && info.st_flags & UInt32(SF_DATALESS) == 0
    }
    private static func readRegular(_ url: URL, maximumBytes: Int) throws -> Data {
        var before = stat()
        guard lstat(url.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG, validSupportEntry(before),
              before.st_size >= 0, before.st_size <= maximumBytes else { throw failure() }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? handle.close() }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, opened.st_dev == before.st_dev, opened.st_ino == before.st_ino,
              opened.st_mode & S_IFMT == S_IFREG, validSupportEntry(opened), opened.st_size == before.st_size else { throw failure() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        var after = stat()
        guard data.count == opened.st_size, data.count <= maximumBytes, fstat(descriptor, &after) == 0, after.st_size == opened.st_size,
              after.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec,
              after.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
        return data
    }
    static func prepare(workspace: URL) throws -> PreparedSampleSession {
        let parent = Paths.physicalURL(workspace), fm = FileManager.default
        var info = stat()
        guard parent.standardizedFileURL.path == workspace.standardizedFileURL.path,
              lstat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, fm.isWritableFile(atPath: parent.path),
              Volumes.free(at: parent) > 1_073_741_824 else { throw failure() }
        try FileTree.validateDestination(parent)
        let root = parent.appendingPathComponent(".DiskWing-samples-\(UUID().uuidString)")
        guard mkdir(root.path, 0o700) == 0 else { throw failure() }
        // Do not delete failed fixture creation; this directory is owned data
        // for diagnosis, never a reason to clean the supplied parent broadly.
        let physicalHome = root.appendingPathComponent("home")
        try fm.createDirectory(at: physicalHome, withIntermediateDirectories: true)
        let home = URL(fileURLWithPath: physicalHome.path, isDirectory: true).standardizedFileURL
        let downloads = home.appendingPathComponent("Downloads")
        try fm.createDirectory(at: downloads.appendingPathComponent("nested"), withIntermediateDirectories: true)
        for number in 0..<150 { try Data(repeating: 65, count: number + 1).write(to: downloads.appendingPathComponent(String(format: "sample-%03d.txt", number))) }
        try Data("generated searchable sample".utf8).write(to: downloads.appendingPathComponent("nested/find-me.txt"))
        for tool in CacheCatalog.all(home: home) {
            try fm.createDirectory(at: tool.source, withIntermediateDirectories: true)
            try Data("generated cache payload".utf8).write(to: tool.source.appendingPathComponent("fixture-artifact"))
        }
        let appCache = home.appendingPathComponent("Library/Caches/com.example.DiskWingSample")
        try fm.createDirectory(at: appCache, withIntermediateDirectories: true)
        try Data("generated application cache".utf8).write(to: appCache.appendingPathComponent("cache.db"))
        try fm.createDirectory(at: root.appendingPathComponent("sample-ssd"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("personal-destination"), withIntermediateDirectories: true)
        let helper = root.appendingPathComponent("sample-helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let store = Store(base: root.appendingPathComponent("support"))
        var settings = AppSettings(); settings.selectedVolumeUUID = "DISKWING-SAMPLE-EXTERNAL"; try store.save(settings)
        var preferences = UserPreferences(); preferences.language = "pt-BR"; try store.write(preferences, name: "preferences.json")
        try Data("diskwing-gui-samples-v1\n".utf8).write(to: root.appendingPathComponent(".diskwing-sample-session"))
        return try validate(session: root)
    }
    static func validate(session: URL) throws -> PreparedSampleSession {
        let root = Paths.physicalURL(session)
        var info = stat()
        guard root.standardizedFileURL.path == session.standardizedFileURL.path, root.lastPathComponent.hasPrefix(".DiskWing-samples-"), UUID(uuidString: String(root.lastPathComponent.dropFirst(".DiskWing-samples-".count))) != nil,
              lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw failure() }
        let required = [root.appendingPathComponent(".diskwing-sample-session"), root.appendingPathComponent("home"), root.appendingPathComponent("support"), root.appendingPathComponent("sample-helper")]
        for url in required {
            guard lstat(url.path, &info) == 0, validSupportEntry(info) else { throw failure() }
        }
        for url in [required[0], required[3]] { guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw failure() } }
        for url in [required[1], required[2]] { guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw failure() } }
        if let files = FileManager.default.enumerator(at: required[2], includingPropertiesForKeys: nil) {
            var count = 0
            for case let file as URL in files {
                count += 1
                guard count <= 4096, lstat(file.path, &info) == 0, validSupportEntry(info) else { throw failure() }
            }
        } else { throw failure() }
        guard try readRegular(required[0], maximumBytes: 64) == Data("diskwing-gui-samples-v1\n".utf8), FileManager.default.isExecutableFile(atPath: required[3].path) else { throw failure() }
        let home = URL(fileURLWithPath: required[1].path, isDirectory: true).standardizedFileURL
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(AppSettings.self, from: readRegular(required[2].appendingPathComponent("settings.json"), maximumBytes: 8_388_608))
        let preferences = required[2].appendingPathComponent("preferences.json")
        if lstat(preferences.path, &info) == 0 {
            let value = try decoder.decode(UserPreferences.self, from: readRegular(preferences, maximumBytes: 8_388_608))
            guard value.schemaVersion == 1 else { throw failure() }
        } else { guard errno == ENOENT else { throw failure() } }
        let online = root.appendingPathComponent("sample-ssd"), offline = root.appendingPathComponent("offline-sample-ssd")
        for folder in [online, offline] {
            if lstat(folder.path, &info) == 0 { guard info.st_mode & S_IFMT == S_IFDIR else { throw failure() } }
            else { guard errno == ENOENT else { throw failure() } }
        }
        let connected = lstat(online.path, &info) == 0
        return PreparedSampleSession(root: root, home: home, support: required[2], helper: required[3], connected: connected, identity: try FileIdentity(root))
    }
}

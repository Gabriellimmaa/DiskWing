import Foundation
import Darwin

public enum Volumes {
    public static func list() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsReadOnlyKey]
        var urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        if !urls.contains(where: { $0.path == "/" }) { urls.insert(URL(fileURLWithPath: "/"), at: 0) }
        var seen = Set<String>()
        return urls.compactMap { url -> VolumeInfo? in
            guard url.path == "/" || url.path.hasPrefix("/Volumes/") else { return nil }
            guard let values = try? url.resourceValues(forKeys: keys), let uuid = values.volumeUUIDString else { return nil }
            guard seen.insert(uuid).inserted else { return nil }
            var fs = statfs()
            let ok = statfs(url.path, &fs) == 0
            let free = ok ? Int64(fs.f_bavail) * Int64(fs.f_bsize) : Int64(values.volumeAvailableCapacity ?? 0)
            return VolumeInfo(uuid: uuid, name: values.volumeName ?? url.lastPathComponent, path: url.path, totalBytes: Int64(values.volumeTotalCapacity ?? 0), freeBytes: free, isInternal: values.volumeIsInternal ?? (url.path == "/"), isWritable: !(values.volumeIsReadOnly ?? true) && FileManager.default.isWritableFile(atPath: url.path))
        }
    }
    public static func find(uuid: String) -> VolumeInfo? { list().first { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame } }
    public static func free(at url: URL) -> Int64 {
        var fs = statfs()
        return statfs(url.path, &fs) == 0 ? Int64(fs.f_bavail) * Int64(fs.f_bsize) : 0
    }
}

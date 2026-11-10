import Foundation
import CoreServices

public struct FolderGrowth: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let logicalDelta: Int64
}

public struct GrowthComparison: Codable, Sendable {
    public let root: String
    public let state: String
    public let reason: String?
    public let previousDate: Date?
    public let latestDate: Date?
    public let logicalDelta: Int64?
    public let allocatedDelta: Int64?
    public let folders: [FolderGrowth]
    public let folderCoverageComplete: Bool
}

extension ScanIndex {
    public func growth(root: String, days: Int? = nil, now: Date = Date(), requireAvailable: Bool = true) throws -> GrowthComparison {
        func unavailable(_ reason: String) -> GrowthComparison {
            GrowthComparison(root: root, state: "unavailable", reason: reason, previousDate: nil, latestDate: nil, logicalDelta: nil, allocatedDelta: nil, folders: [], folderCoverageComplete: false)
        }
        let snapshots = try execute("SELECT * FROM snapshots WHERE root=? ORDER BY time DESC", [.text(root)])
        guard let newest = snapshots.first else { return unavailable("Ainda não há uma análise para comparar.") }
        guard Self.string(newest, "state") == "complete" else { return unavailable("A análise mais recente é parcial e não comprova crescimento ou economia.") }
        if requireAvailable {
            guard !Self.string(newest,"volume").isEmpty else { return unavailable("A identidade do volume não está disponível; faça uma nova análise.") }
            let path = URL(fileURLWithPath: root)
            guard FileManager.default.isReadableFile(atPath: root) else { return unavailable("A pasta ou o SSD está indisponível. Ausência não é espaço liberado.") }
            let currentVolume = (try? path.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? ""
            guard currentVolume == Self.string(newest, "volume") else { return unavailable("O volume mudou; faça uma nova análise antes de comparar.") }
        }
        let threshold = days.map { now.addingTimeInterval(-Double(max(1,$0)) * 86400).timeIntervalSince1970 }
        guard let old = snapshots.dropFirst().first(where: { Self.string($0,"state") == "complete" && (threshold == nil || Self.double($0,"time") <= threshold!) }) else {
            return unavailable(days == nil ? "Faça outra análise para observar a variação." : "Ainda não há uma análise antiga suficiente para esse período.")
        }
        guard Self.string(old,"volume") == Self.string(newest,"volume") else { return unavailable("As análises pertencem a volumes diferentes.") }
        let latestID = Self.string(newest,"id"), oldID = Self.string(old,"id")
        let complete = Self.integer(newest,"folderComplete") == 1 && Self.integer(old,"folderComplete") == 1
        let query: String
        if complete {
            query = """
            WITH paths AS (SELECT path FROM folder_samples WHERE snapshot=? UNION SELECT path FROM folder_samples WHERE snapshot=?)
            SELECT paths.path,COALESCE(new.logical,0)-COALESCE(old.logical,0) AS delta FROM paths
            LEFT JOIN folder_samples new ON new.path=paths.path AND new.snapshot=?
            LEFT JOIN folder_samples old ON old.path=paths.path AND old.snapshot=?
            WHERE paths.path<>'' ORDER BY ABS(delta) DESC LIMIT 20
            """
        } else {
            query = """
            WITH paths AS (SELECT path FROM folder_samples WHERE snapshot=? INTERSECT SELECT path FROM folder_samples WHERE snapshot=?)
            SELECT paths.path,new.logical-old.logical AS delta FROM paths
            JOIN folder_samples new ON new.path=paths.path AND new.snapshot=?
            JOIN folder_samples old ON old.path=paths.path AND old.snapshot=?
            WHERE paths.path<>'' ORDER BY ABS(delta) DESC LIMIT 20
            """
        }
        let folders = try execute(query, [.text(latestID),.text(oldID),.text(latestID),.text(oldID)]).map {
            FolderGrowth(path: URL(fileURLWithPath: root).appendingPathComponent(Self.string($0,"path")).path, logicalDelta: Self.integer($0,"delta"))
        }
        return GrowthComparison(root: root, state: "comparable", reason: complete ? nil : "Variação por pasta limitada às pastas presentes nas duas amostras.", previousDate: Date(timeIntervalSince1970: Self.double(old,"time")), latestDate: Date(timeIntervalSince1970: Self.double(newest,"time")), logicalDelta: Self.integer(newest,"logical")-Self.integer(old,"logical"), allocatedDelta: Self.integer(newest,"allocated")-Self.integer(old,"allocated"), folders: folders, folderCoverageComplete: complete)
    }
}

/// Events are invalidation hints, never an authoritative record of reclaimed bytes.
public final class DirectoryEventMonitor {
    private final class Callback {
        let excluded: [String]
        let onChange: (Bool) -> Void
        init(excluded: [URL], onChange: @escaping (Bool) -> Void) { self.excluded = excluded.map(\.path); self.onChange = onChange }
    }
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "DiskWing.filesystem-events", qos: .utility)
    public init(root: URL, excluding: [URL] = [Paths.support], onChange: @escaping (Bool) -> Void) throws {
        let callback = Callback(excluded: excluding, onChange: onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in guard let pointer else { return nil }; _ = Unmanaged<Callback>.fromOpaque(UnsafeMutableRawPointer(mutating: pointer)).retain(); return pointer },
            release: { pointer in if let pointer { Unmanaged<Callback>.fromOpaque(UnsafeMutableRawPointer(mutating: pointer)).release() } }, copyDescription: nil)
        stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, count, eventPaths, flags, _ in
            guard let info else { return }
            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var changed = false, full = false
            for offset in 0..<count {
                let path = offset < paths.count ? paths[offset] : ""
                if callback.excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
                changed = true
                if flags[offset] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped) != 0 { full = true }
            }
            if changed { callback.onChange(full) }
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        guard let stream else { throw CacheSSDError.message(L10n.text("Não foi possível acompanhar esta pasta.")) }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil
            throw CacheSSDError.message(L10n.text("O acompanhamento da pasta não pôde ser iniciado."))
        }
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}

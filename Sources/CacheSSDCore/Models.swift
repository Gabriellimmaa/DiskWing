import Foundation
import Darwin

public enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case personal = "Arquivos pessoais"
    case cache = "Cache reconhecido"
    case developer = "Ferramentas e desenvolvimento"
    case application = "Aplicativos e bibliotecas"
    case system = "Sistema e dados de aplicativos"
    case unknown = "Outros arquivos"
}

public struct ScanItem: Identifiable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let category: ContentCategory
    public let issue: String?
    public let children: [ScanItem]
    public var fileIdentity: FileIdentity? = nil
    public var url: URL { URL(fileURLWithPath: path) }
}

public struct ScanReport: Codable, Sendable {
    public let id: UUID
    public let root: ScanItem
    public let startedAt: Date
    public let finishedAt: Date
    public let examinedEntries: Int
    public let unreadablePaths: [String]
    public let skippedMounts: [String]
    public let isCancelled: Bool
    public let reachedLimit: Bool
    public let largestFiles: [ScanItem]
    public var isPartial: Bool { isCancelled || reachedLimit || !unreadablePaths.isEmpty }
}

public struct ScanProgress: Sendable {
    public let entries: Int
    public let logicalBytes: Int64
    public let currentPath: String
}

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

public struct VolumeInfo: Identifiable, Codable, Sendable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let isInternal: Bool
    public let isWritable: Bool
}

public struct OperationRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let detail: String
    public let measuredFreeDelta: Int64?
    public let recoveryPath: String?
    public init(title: String, detail: String, measuredFreeDelta: Int64? = nil, recoveryPath: String? = nil) {
        id = UUID(); date = Date(); self.title = title; self.detail = detail
        self.measuredFreeDelta = measuredFreeDelta; self.recoveryPath = recoveryPath
    }
}

public enum CacheSSDError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let value) = self { return L10n.message(value) }; return nil }
}

public enum ByteText {
    public static func format(_ bytes: Int64) -> String {
        max(0, bytes).formatted(.byteCount(style: .file).locale(L10n.locale))
    }
}

public enum Paths {
    public static var support: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CacheSSD", isDirectory: true) }
    public static func contains(_ path: URL, in parent: URL) -> Bool {
        let p = path.standardizedFileURL.path, r = parent.standardizedFileURL.path
        return p == r || p.hasPrefix(r == "/" ? "/" : r + "/")
    }
    public static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\n") && !value.contains("\t")
    }
    // Foundation can abbreviate /private/var to /var, while directory enumerators
    // return the physical spelling. Use realpath for relative manifest paths.
    public static func physicalURL(_ url: URL) -> URL {
        guard let pointer = realpath(url.path, nil) else { return url }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer))
    }
}

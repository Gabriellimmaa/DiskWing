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

public enum ScanCoverage: String, Codable, Sendable {
    case complete, partial, unknown
    var databaseValue: Int64 { self == .complete ? 0 : self == .partial ? 1 : 2 }
    init(databaseValue: Int64) { self = databaseValue == 0 ? .complete : databaseValue == 1 ? .partial : .unknown }
    static func legacy(issue: String?, isLink: Bool, children: [ScanItem]) -> ScanCoverage {
        if isLink { return .unknown }
        if let issue {
            if issue.hasPrefix("Blocos ") || issue.hasPrefix("Exibindo os ") { }
            else if issue.contains("nuvem") || issue.contains("parcial") || issue.contains("limite") { return .partial }
            else { return .unknown }
        }
        return children.contains { !$0.isSymbolicLink && $0.coverage != .complete } ? .partial : .complete
    }
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
    public var coverage: ScanCoverage
    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, name: String, isDirectory: Bool, isSymbolicLink: Bool, logicalBytes: Int64, allocatedBytes: Int64, fileCount: Int, category: ContentCategory, issue: String?, children: [ScanItem], fileIdentity: FileIdentity? = nil, coverage: ScanCoverage? = nil) {
        self.path = path; self.name = name; self.isDirectory = isDirectory; self.isSymbolicLink = isSymbolicLink
        self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes; self.fileCount = fileCount
        self.category = category; self.issue = issue; self.children = children; self.fileIdentity = fileIdentity
        self.coverage = coverage ?? ScanCoverage.legacy(issue: issue, isLink: isSymbolicLink, children: children)
    }
    private enum CodingKeys: String, CodingKey { case path, name, isDirectory, isSymbolicLink, logicalBytes, allocatedBytes, fileCount, category, issue, children, fileIdentity, coverage }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path); name = try values.decode(String.self, forKey: .name)
        isDirectory = try values.decode(Bool.self, forKey: .isDirectory); isSymbolicLink = try values.decode(Bool.self, forKey: .isSymbolicLink)
        logicalBytes = try values.decode(Int64.self, forKey: .logicalBytes); allocatedBytes = try values.decode(Int64.self, forKey: .allocatedBytes)
        fileCount = try values.decode(Int.self, forKey: .fileCount); category = try values.decode(ContentCategory.self, forKey: .category)
        issue = try values.decodeIfPresent(String.self, forKey: .issue); children = try values.decode([ScanItem].self, forKey: .children)
        fileIdentity = try values.decodeIfPresent(FileIdentity.self, forKey: .fileIdentity)
        if values.contains(.coverage) { coverage = (try? values.decode(ScanCoverage.self, forKey: .coverage)) ?? .unknown }
        else { coverage = ScanCoverage.legacy(issue: issue, isLink: isSymbolicLink, children: children) }
    }
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
    public var isPartial: Bool { isCancelled || reachedLimit || !unreadablePaths.isEmpty || !skippedMounts.isEmpty || root.coverage != .complete }
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

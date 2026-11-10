import Foundation

public enum CacheUsageState: String, Codable, CaseIterable, Sendable {
    case none, transferring, configuredNeedsReopen, ssdVerified, localTemporary, exception, error
}

public enum CacheTransferEntryKind: String, Codable, Sendable { case commandLine, graphical }

public struct CacheTransferEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let kind: CacheTransferEntryKind
    public let title: String
    public let scopeLabel: String
    public let sourceURL: URL
    public let destinationURL: URL?
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let canReleaseSource: Bool
    public let requiresReopen: Bool
    public let isSourceMissing: Bool
    public let blockedReason: String?
    public init(id: String, kind: CacheTransferEntryKind, title: String, scopeLabel: String, sourceURL: URL,
                destinationURL: URL? = nil, logicalBytes: Int64, allocatedBytes: Int64,
                canReleaseSource: Bool, requiresReopen: Bool, isSourceMissing: Bool = false, blockedReason: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.scopeLabel = scopeLabel; self.sourceURL = sourceURL
        self.destinationURL = destinationURL; self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes
        self.canReleaseSource = canReleaseSource; self.requiresReopen = requiresReopen
        self.isSourceMissing = isSourceMissing; self.blockedReason = blockedReason
    }
}

public struct CacheTransferPlan: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let destinationVolume: VolumeInfo
    public let entries: [CacheTransferEntry]
    public var eligibleEntries: [CacheTransferEntry] { entries.filter { $0.blockedReason == nil } }
    public var eligibleLogicalBytes: Int64 { eligibleEntries.reduce(0) { $0 + $1.logicalBytes } }
    public init(destinationVolume: VolumeInfo, entries: [CacheTransferEntry]) {
        id = UUID(); createdAt = Date(); self.destinationVolume = destinationVolume; self.entries = entries
    }
}

public struct CacheTransferProgress: Sendable {
    public let entryID: String
    public let state: CacheUsageState
    public let detail: String
    public init(entryID: String, state: CacheUsageState, detail: String) { self.entryID = entryID; self.state = state; self.detail = detail }
}

public struct CacheTransferItemResult: Identifiable, Codable, Sendable {
    public let id: String
    public let state: CacheUsageState
    public let detail: String
    public let recordID: UUID?
    public let sourceReleased: Bool
    public let sourceLogicalBytes: Int64
    public init(id: String, state: CacheUsageState, detail: String, recordID: UUID? = nil, sourceReleased: Bool = false, sourceLogicalBytes: Int64 = 0) {
        self.id = id; self.state = state; self.detail = detail; self.recordID = recordID
        self.sourceReleased = sourceReleased; self.sourceLogicalBytes = sourceLogicalBytes
    }
}

import Foundation
import Darwin

public struct ConfigurationChange: Codable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let before: String
    public let after: String
    public var state = "prepared"
    public let date: Date
    public init(source: String, before: String, after: String) { schemaVersion = 1; date = Date(); self.source = source; self.before = before; self.after = after }
}

public struct AppSettings: Codable, Sendable {
    public var installationID = UUID().uuidString
    public var selectedVolumeUUID: String?
    public var useExternal = true
    public var shellIntegrationEnabled = false
    public var locations: [String: CacheLocation] = [:]
    public init() {}
}

public struct CacheLocation: Codable, Sendable {
    public var toolID: String
    public var volumeUUID: String
    public var relativePath: String
    public var migratedAt: Date
    public var logicalBytes: Int64
}

public final class Store {
    public let base: URL
    public init(base: URL = Paths.support) { self.base = base }
    public func settings() -> AppSettings {
        (try? read(AppSettings.self, name: "settings.json")) ?? AppSettings()
    }
    public func save(_ settings: AppSettings) throws {
        let file = base.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: file.path) {
            guard (try? read(AppSettings.self, name: "settings.json")) != nil else { throw CacheSSDError.message(L10n.text("O registro de configuração está ilegível e foi preservado. Use o backup em settings-previous.json para recuperá-lo.")) }
            let old = try Data(contentsOf: file)
            try old.write(to: base.appendingPathComponent("settings-previous.json"), options: .atomic)
        }
        try write(settings, name: "settings.json")
    }
    public func interruptedMigrations() -> [MigrationJournal] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return names.filter { $0.hasPrefix("migration-") && $0.hasSuffix(".json") }.compactMap { try? read(MigrationJournal.self, name: $0) }.filter { $0.state != "completed" }.sorted { $0.startedAt > $1.startedAt }
    }
    public func history() -> [OperationRecord] { (try? read([OperationRecord].self, name: "history.json")) ?? [] }
    public func operations() -> [OperationJournal] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return names.filter { $0.hasPrefix("operation-") && $0.hasSuffix(".json") }
            .compactMap { try? read(OperationJournal.self, name: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func unreadableOperationRecords() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return names.filter { $0.hasPrefix("operation-") && $0.hasSuffix(".json") && (try? read(OperationJournal.self, name: $0)) == nil }.sorted()
    }
    public func pendingConfigurationRecords() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return names.filter { $0.hasPrefix("configuration-") && $0.hasSuffix(".json") && (try? read(ConfigurationChange.self, name: $0).state) != "completed" }.sorted()
    }
    public func pruneCompletedOperations(keeping count: Int = 150) throws {
        // Pending and unreadable records are never discarded by retention.
        for journal in operations().filter({ !$0.isPending }).dropFirst(max(0,count)) {
            try FileManager.default.removeItem(at: base.appendingPathComponent("operation-\(journal.id.uuidString).json"))
        }
    }
    public func writeDurably<T: Encodable>(_ value: T, name: String) throws {
        try write(value, name: name)
        let descriptor = open(base.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível confirmar o registro da operação.")) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível persistir o registro da operação.")) }
        let directory = open(base.path, O_RDONLY | O_CLOEXEC)
        guard directory >= 0 else { throw CacheSSDError.message(L10n.text("O diretório de registros está indisponível.")) }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw CacheSSDError.message(L10n.text("Não foi possível persistir a pasta de registros.")) }
    }
    public func append(_ record: OperationRecord) throws {
        var records = history(); records.insert(record, at: 0)
        try write(Array(records.prefix(150)), name: "history.json")
        try pruneCompletedOperations()
    }
    public func saveReport(_ report: ScanReport) throws {
        struct Summary: Codable { let date: Date; let root: String; let logical: Int64; let allocated: Int64; let partial: Bool }
        var values = (try? read([Summary].self, name: "scans.json")) ?? []
        values.insert(Summary(date: report.finishedAt, root: report.root.path, logical: report.root.logicalBytes, allocated: report.root.allocatedBytes, partial: report.isPartial), at: 0)
        try write(Array(values.prefix(50)), name: "scans.json")
    }
    public func write<T: Encodable>(_ value: T, name: String) throws {
        guard Paths.safeComponent(name) else { throw CacheSSDError.message(L10n.text("Nome de registro inválido.")) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: base.appendingPathComponent(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: base.appendingPathComponent(name).path)
    }
    public func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: base.appendingPathComponent(name)))
    }
}

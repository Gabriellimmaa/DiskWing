import Foundation

public struct WatchedFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let volumeUUID: String
    public init(path: String, volumeUUID: String) { self.path = path; self.volumeUUID = volumeUUID }
}

public struct UserPreferences: Codable, Sendable {
    public var schemaVersion = 1
    public var language = "system"
    public var watchedFolders: [WatchedFolder] = []
    public var backgroundRescans = true
    public var growthAlerts = false
    public var growthThresholdBytes: Int64 = 1_073_741_824
    public var lastAlerts: [String: Date] = [:]
    public init() {}
}

extension Store {
    public func preferences() throws -> UserPreferences {
        guard FileManager.default.fileExists(atPath: base.appendingPathComponent("preferences.json").path) else { return UserPreferences() }
        let value = try read(UserPreferences.self, name: "preferences.json")
        guard value.schemaVersion == 1 else { throw CacheSSDError.message(L10n.text("As preferências pertencem a outra versão e foram preservadas.")) }
        return value
    }
}

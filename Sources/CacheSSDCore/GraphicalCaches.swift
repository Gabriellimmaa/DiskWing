import Foundation
import Darwin
import Security

public struct GraphicalCacheCandidate: Identifiable, Codable, Sendable {
    public let id: String
    public let applicationID: String
    public let applicationName: String
    public let applicationVersion: String?
    public let applicationURL: URL?
    public let sourceURL: URL
    public let scopeLabel: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let measurementComplete: Bool
    public let isMissing: Bool
    public let canTransfer: Bool
    public let blockedReason: String?
    public let isSimulated: Bool
    public init(id: String, applicationID: String, applicationName: String, applicationVersion: String?, applicationURL: URL?,
                sourceURL: URL, scopeLabel: String, logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0,
                measurementComplete: Bool = true, isMissing: Bool = false, canTransfer: Bool = false,
                blockedReason: String? = nil, isSimulated: Bool = false) {
        self.id = id; self.applicationID = applicationID; self.applicationName = applicationName
        self.applicationVersion = applicationVersion; self.applicationURL = applicationURL; self.sourceURL = sourceURL
        self.scopeLabel = scopeLabel; self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes
        self.measurementComplete = measurementComplete; self.isMissing = isMissing
        self.canTransfer = canTransfer; self.blockedReason = blockedReason; self.isSimulated = isSimulated
    }
    public func transferEntry(destinationURL: URL? = nil) -> CacheTransferEntry {
        CacheTransferEntry(id: id, kind: .graphical, title: applicationName, scopeLabel: scopeLabel, sourceURL: sourceURL,
                           destinationURL: destinationURL, logicalBytes: logicalBytes, allocatedBytes: allocatedBytes,
                           canReleaseSource: canTransfer, requiresReopen: true, isSourceMissing: isMissing,
                           blockedReason: canTransfer ? nil : blockedReason ?? "Este cache ainda não tem uma transferência qualificada.")
    }
}

public struct GraphicalCacheStatus: Codable, Sendable {
    public let candidateID: String
    public let state: CacheUsageState
    public let detail: String
    public let recordID: UUID?
    public let destinationURL: URL?
    public let sourceReleased: Bool
    public let verifiedAt: Date?
    public init(candidateID: String, state: CacheUsageState, detail: String, recordID: UUID? = nil,
                destinationURL: URL? = nil, sourceReleased: Bool = false, verifiedAt: Date? = nil) {
        self.candidateID = candidateID; self.state = state; self.detail = detail; self.recordID = recordID
        self.destinationURL = destinationURL; self.sourceReleased = sourceReleased; self.verifiedAt = verifiedAt
    }
}

public enum GraphicalCacheCatalog {
    public static let chromeCacheID = "chrome.cache-root"
    public static let chromeBundleID = "com.google.Chrome"
    public static let chromeRelativePath = "Library/Caches/Google/Chrome"
    // Exact versions are added only after generated native application evidence.
    public static let qualifiedChromeVersions: Set<String> = ["157.0.8103.39"]
    public static var platformIsQualified: Bool {
        #if arch(arm64)
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
        #else
        return false
        #endif
    }
    static func chromeHasCustomStorage() -> Bool {
        let preferences = UserDefaults(suiteName: chromeBundleID)
        return ["DiskCacheDir", "UserDataDir"].contains { preferences?.object(forKey: $0) != nil }
    }
    static func chromeSignatureIsQualified(_ application: URL) -> Bool {
        var code: SecStaticCode?, requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"com.google.Chrome\" and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(rawValue: 0), &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(application as CFURL, SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }
    static func chromeProcessRequirement() -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"" as CFString,
                                            SecCSFlags(rawValue: 0), &requirement) == errSecSuccess else { return nil }
        return requirement
    }
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  applications: [URL] = [URL(fileURLWithPath: "/Applications")]) -> [GraphicalCacheCandidate] {
        GenericAppDetector.discover(home: home, applications: applications)
    }
}

public enum GenericAppDetector {
    private struct Definition {
        let id: String, bundleID: String, name: String, bundle: String, relativeCache: String, scope: String, exception: String
    }
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                applications: [URL] = [URL(fileURLWithPath: "/Applications")]) -> [GraphicalCacheCandidate] {
        let definitions = [
            Definition(id: GraphicalCacheCatalog.chromeCacheID, bundleID: GraphicalCacheCatalog.chromeBundleID, name: "Google Chrome", bundle: "Google Chrome.app", relativeCache: GraphicalCacheCatalog.chromeRelativePath,
                       scope: "Diretório de caches derivado do Chrome em Library/Caches. Caches gráficos, componentes e dados de perfil em Application Support ficam no Mac.", exception: "Esta versão do Chrome ainda não tem transferência e retorno sem SSD qualificados."),
            Definition(id: "chrome.gpu-persistent-cache", bundleID: GraphicalCacheCatalog.chromeBundleID, name: "Google Chrome", bundle: "Google Chrome.app", relativeCache: "Library/Application Support/Google/Chrome/GPUPersistentCache",
                       scope: "Somente GPUPersistentCache do Chrome; medição separada do cache transferível.", exception: "Este subcache fica junto aos dados do Chrome e será preservado; sua transferência não foi qualificada."),
            Definition(id: "chrome.graphite-cache", bundleID: GraphicalCacheCatalog.chromeBundleID, name: "Google Chrome", bundle: "Google Chrome.app", relativeCache: "Library/Application Support/Google/Chrome/GraphiteDawnCache",
                       scope: "Somente GraphiteDawnCache do Chrome; medição separada do cache transferível.", exception: "Este subcache fica junto aos dados do Chrome e será preservado; sua transferência não foi qualificada."),
            Definition(id: "chrome.component-cache", bundleID: GraphicalCacheCatalog.chromeBundleID, name: "Google Chrome", bundle: "Google Chrome.app", relativeCache: "Library/Application Support/Google/Chrome/component_crx_cache",
                       scope: "Somente pacotes em component_crx_cache do Chrome; componentes instalados ficam no Mac.", exception: "Este subcache fica junto aos dados do Chrome e será preservado; sua transferência não foi qualificada."),
            Definition(id: "chrome.extension-cache", bundleID: GraphicalCacheCatalog.chromeBundleID, name: "Google Chrome", bundle: "Google Chrome.app", relativeCache: "Library/Application Support/Google/Chrome/extensions_crx_cache",
                       scope: "Somente pacotes em extensions_crx_cache do Chrome; extensões instaladas e seus dados ficam no Mac.", exception: "Este subcache fica junto aos dados do Chrome e será preservado; sua transferência não foi qualificada."),
            Definition(id: "cursor.http-cache", bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", bundle: "Cursor.app", relativeCache: "Library/Application Support/Cursor/Cache",
                       scope: "Cache HTTP do Cursor; projetos, extensões, contas e configurações ficam no Mac.", exception: "O cache do Cursor ainda não tem transferência e retorno sem SSD qualificados."),
            Definition(id: "xcode.derived-data", bundleID: "com.apple.dt.Xcode", name: "Xcode", bundle: "Xcode.app", relativeCache: "Library/Developer/Xcode/DerivedData",
                       scope: "Derived Data do Xcode; SDKs, simuladores, projetos e arquivos de distribuição ficam no Mac.", exception: "O Xcode possui configuração própria de Derived Data. O retorno automático sem SSD ainda não foi qualificado."),
            Definition(id: "safari.http-cache", bundleID: "com.apple.Safari", name: "Safari", bundle: "Safari.app", relativeCache: "Library/Caches/com.apple.Safari",
                       scope: "Raiz histórica de caches do Safari; caminho efetivo e tamanho completo não confirmados. Perfis, cookies e senhas ficam no Mac.", exception: "Os caches do Safari são protegidos pelo macOS. Nenhum redirecionamento seguro foi qualificado.")
        ]
        return definitions.map { definition in
            let bundleURL = applications.map { $0.appendingPathComponent(definition.bundle) }.first { FileManager.default.fileExists(atPath: $0.path) }
            let info = bundleURL.flatMap { readBundleInfo($0) }
            let matched = info?["CFBundleIdentifier"] as? String == definition.bundleID
            let version = matched ? info?["CFBundleShortVersionString"] as? String : nil
            let source = home.appendingPathComponent(definition.relativeCache)
            let size = FileTree.measure(source)
            let chrome = definition.id == GraphicalCacheCatalog.chromeCacheID
            let signedChrome = chrome && bundleURL.map(GraphicalCacheCatalog.chromeSignatureIsQualified) == true
            let qualified = chrome && GraphicalCacheCatalog.platformIsQualified && version.map { GraphicalCacheCatalog.qualifiedChromeVersions.contains($0) } == true && signedChrome
            let customChrome = definition.id == GraphicalCacheCatalog.chromeCacheID && GraphicalCacheCatalog.chromeHasCustomStorage()
            let reason: String?
            if !matched { reason = "Aplicativo não localizado; nenhum cache será alterado." }
            else if customChrome { reason = "O Chrome usa uma configuração de cache ou perfil personalizada. Ela foi preservada." }
            else if source.standardizedFileURL != source.resolvingSymlinksInPath() { reason = "Este cache já usa um caminho redirecionado. Revise seu registro antes de alterar." }
            else if !size.missing && !size.isComplete { reason = "A medição deste cache está incompleta; ele será preservado." }
            else if chrome && !GraphicalCacheCatalog.platformIsQualified { reason = "A transferência deste cache só foi qualificada em Apple Silicon com macOS 26 e SSD APFS." }
            else if chrome && !signedChrome { reason = "A identidade assinada desta instalação do Chrome não corresponde à distribuição qualificada. O cache será preservado." }
            else if !qualified { reason = definition.exception }
            else { reason = nil }
            return GraphicalCacheCandidate(id: definition.id, applicationID: definition.bundleID, applicationName: definition.name,
                                           applicationVersion: version, applicationURL: matched ? bundleURL : nil,
                                           sourceURL: source, scopeLabel: definition.scope, logicalBytes: size.logical,
                                           allocatedBytes: size.allocated, measurementComplete: definition.id != "safari.http-cache" && (size.isComplete || size.missing),
                                           isMissing: size.missing, canTransfer: reason == nil, blockedReason: reason)
        }
    }
    static func readBundleInfo(_ bundle: URL) -> [String: Any]? {
        let path = bundle.appendingPathComponent("Contents/Info.plist")
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_flags & UInt32(SF_DATALESS) == 0, metadata.st_size <= 1_048_576,
              let bytes = try? file.read(upToCount: 1_048_577), bytes.count <= 1_048_576 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: bytes, format: nil)) as? [String: Any]
    }
}

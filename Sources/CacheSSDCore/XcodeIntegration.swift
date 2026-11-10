import Foundation

public enum XcodeIntegration {
    public static func useLocalDerivedData(store: Store = Store()) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        let running = try CommandRunner.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "comm="], timeout: 10)
        guard running.status == 0, !running.output.contains("/Xcode.app/Contents/MacOS/Xcode") else { throw CacheSSDError.message(L10n.text("Encerre o Xcode antes de alterar o local dos arquivos de compilação.")) }
        let domain = "com.apple.dt.Xcode"
        let exported = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/defaults"), ["export", domain, "-"], maxOutputBytes: 4_194_304)
        guard exported.status == 0, !exported.truncated,
              (try? PropertyListSerialization.propertyList(from: Data(exported.output.utf8), format: nil)) != nil else { throw CacheSSDError.message(L10n.text("Não foi possível conferir as preferências do Xcode. Nenhuma alteração foi iniciada.")) }
        let changeName = "configuration-\(UUID().uuidString).json"
        var change = ConfigurationChange(source: domain, before: exported.output, after: "IDEDerivedDataLocationStyle=Default; IDECustomDerivedDataLocation absent")
        try store.writeDurably(change, name: changeName)
        var backup: [String: String] = [:]
        for key in ["IDECustomDerivedDataLocation", "IDEDerivedDataLocationStyle"] {
            let result = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/defaults"), ["read", domain, key])
            if result.status == 0 { backup[key] = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if !FileManager.default.fileExists(atPath: store.base.appendingPathComponent("xcode-before-local.json").path) { try store.writeDurably(backup, name: "xcode-before-local.json") }
        let set = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/defaults"), ["write", domain, "IDEDerivedDataLocationStyle", "-string", "Default"])
        guard set.status == 0 else { throw CacheSSDError.message(L10n.text("O macOS não permitiu alterar a preferência do Xcode. O backup foi preservado.")) }
        if backup["IDECustomDerivedDataLocation"] != nil {
            let remove = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/defaults"), ["delete", domain, "IDECustomDerivedDataLocation"])
            guard remove.status == 0 else { throw CacheSSDError.message(L10n.text("A preferência anterior do Xcode não pôde ser removida. Consulte o backup antes de tentar novamente.")) }
        }
        try store.append(OperationRecord(title: "Xcode usando armazenamento local", detail: "Derived Data voltou ao padrão do Mac. Os arquivos de compilação existentes no SSD foram preservados.", recoveryPath: store.base.appendingPathComponent("xcode-before-local.json").path))
        change.state = "completed"; try store.writeDurably(change, name: changeName)
    }
}

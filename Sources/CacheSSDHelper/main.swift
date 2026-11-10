import Foundation
import CacheSSDCore
import Darwin

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(value)); print("")
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"
let store = Store()
do {
    switch command {
    case "shell-env":
        let settings = store.settings()
        guard settings.shellIntegrationEnabled else { exit(0) }
        var excluded = Set<String>()
        if args.contains("--omit-bun") { excluded.insert("bun") }
        if args.contains("--omit-uv") { excluded.insert("uv") }
        for (key, value) in CacheRouter.environment(settings: settings, excluding: excluded).sorted(by: { $0.key < $1.key }) {
            if !value.contains("\n"), !value.contains("\t") { print("\(key)\t\(value)") }
        }
    case "status":
        try printJSON(CacheRouter.decisions(settings: store.settings()))
    case "volumes": try printJSON(Volumes.list())
    case "scan":
        guard args.count >= 2 else { throw CacheSSDError.message("Informe uma pasta: CacheSSDHelper scan /caminho") }
        let report = try DiskScanner().scan(URL(fileURLWithPath: args[1]))
        try printJSON(report)
    case "inventory":
        struct Entry: Encodable { let id: String; let name: String; let path: String; let bytes: Int64; let allocated: Int64 }
        try printJSON(CacheCatalog.all().map { tool in let size = FileTree.measure(tool.source); return Entry(id: tool.id, name: tool.name, path: tool.source.path, bytes: size.logical, allocated: size.allocated) })
    case "migrate":
        guard args.count >= 2, args.contains("--apply") else { throw CacheSSDError.message("A migração altera arquivos. Revise no aplicativo ou use migrate TOOL --apply [--release-local].") }
        let record = try MigrationEngine().migrate(toolID: args[1], removeLocal: args.contains("--release-local"), progress: { message in FileHandle.standardError.write(Data((message + "\n").utf8)) })
        try printJSON(record)
    case "restore":
        guard args.count >= 2, args.contains("--apply") else { throw CacheSSDError.message("Use restore TOOL --apply depois de revisar a cópia e o espaço disponível.") }
        try MigrationEngine().restore(toolID: args[1]); print("Cache restaurado.")
    case "run":
        var values = Array(args.dropFirst()); if values.first == "--" { values.removeFirst() }
        guard let name = values.first else { throw CacheSSDError.message("Use CacheSSDHelper run -- comando argumentos") }
        let path = name.contains("/") ? URL(fileURLWithPath: name) : ToolLocator.locate(name)
        guard let executable = path else { throw CacheSSDError.message("Comando não encontrado.") }
        var environment = ProcessInfo.processInfo.environment
        var excluded = Set<String>()
        if values.contains(where: { $0.hasPrefix("--backend") || $0.hasPrefix("--global-store") }) { excluded.insert("bun") }
        if values.contains(where: { $0.hasPrefix("--link-mode") }) { excluded.insert("uv") }
        for (key,value) in CacheRouter.environment(settings: store.settings(), excluding: excluded) where environment[key] == nil { environment[key] = value }
        let child = Process(); child.executableURL = executable; child.arguments = Array(values.dropFirst()); child.environment = environment
        child.standardInput = FileHandle.standardInput; child.standardOutput = FileHandle.standardOutput; child.standardError = FileHandle.standardError
        try child.run(); child.waitUntilExit(); exit(child.terminationStatus)
    default:
        print("""
        CacheSSD Helper
          volumes                      Lista discos e espaço livre
          scan PASTA                   Analisa metadados; não altera arquivos
          inventory                    Mede caches locais reconhecidos
          status                       Mostra o destino de cada integração
          run -- COMANDO ARGUMENTOS    Executa com o cache compatível disponível
          migrate TOOL --apply         Copia e valida um cache selecionado
            --release-local            Libera a origem após validar a cópia
          restore TOOL --apply         Restaura uma cópia quando há espaço local
        Ferramentas: npm, bun, cocoapods, pip, homebrew, gradle, uv.
        """)
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}

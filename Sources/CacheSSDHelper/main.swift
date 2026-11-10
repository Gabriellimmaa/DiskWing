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
    case "acceptance-check":
        guard args.count == 5, args[1] == "--workspace", args[3] == "--output" else { throw CacheSSDError.message("Use acceptance-check --workspace EXISTING_FIXTURE_DIRECTORY --output NEW_REPORT.json. Only generated fixtures are changed.") }
        let output = URL(fileURLWithPath: args[4]).standardizedFileURL
        var existing = stat()
        guard lstat(output.path, &existing) != 0, errno == ENOENT,
              Paths.physicalURL(output.deletingLastPathComponent()).standardizedFileURL.path == output.deletingLastPathComponent().standardizedFileURL.path,
              FileManager.default.isWritableFile(atPath: output.deletingLastPathComponent().path) else { throw CacheSSDError.message("Choose a new report filename in an existing writable directory without links.") }
        let report = try AcceptanceRunner.run(workspace: URL(fileURLWithPath: args[2]), helper: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL)
        try report.write(to: output)
        try printJSON(report)
        if !report.passed { exit(1) }
    case "self-check":
        L10n.preference = "en"
        let qualifications = CacheAdapters.qualifiedVersions
        guard !L10n.english.isEmpty, L10n.text("Nome") == "Name", CacheAdapters.hasValidBundledQualifications else { throw CacheSSDError.message("Required application resources are unavailable.") }
        print("DiskWing resources verified: PT/EN and \(qualifications.count) cache qualifications")
    case "shell-env":
        let settings = store.settings()
        guard settings.shellIntegrationEnabled else { exit(0) }
        let excluded = Set(CacheCatalog.all().map(\.id).filter { args.contains("--omit-" + $0) })
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
    case "index":
        guard args.count >= 2 else { throw CacheSSDError.message("Informe uma pasta para indexar.") }
        let database = try ScanIndex()
        let report = try IndexedScanner().scan(URL(fileURLWithPath: args[1]), index: database)
        try printJSON(report)
    case "search":
        guard args.count >= 3, let id = UUID(uuidString: args[1]) else { throw CacheSSDError.message("Use search SESSION QUERY.") }
        try printJSON(ScanIndex().page(sessionID: id, search: args[2]).items)
    case "operations":
        try printJSON(store.operations())
    case "recover":
        guard args.count >= 2, let id = UUID(uuidString: args[1]), args.contains("--apply") else { throw CacheSSDError.message("Use recover ID --apply após revisar o registro.") }
        try RecoveryManager().restoreSource(id: id); print("Origem recuperada.")
    case "resolve":
        guard args.count >= 2, let id = UUID(uuidString: args[1]), args.contains("--apply") else { throw CacheSSDError.message("Use resolve ID --apply para encerrar mantendo todas as cópias.") }
        try RecoveryManager().keepCopiesAndResolve(id: id); print("Registro encerrado; cópias preservadas.")
    case "inventory":
        struct Entry: Encodable { let id: String; let name: String; let path: String; let bytes: Int64; let allocated: Int64; let complete: Bool; let missing: Bool }
        try printJSON(CacheCatalog.all().map { tool in let size = FileTree.measure(tool.source); return Entry(id: tool.id, name: tool.name, path: tool.source.path, bytes: size.logical, allocated: size.allocated, complete: size.isComplete, missing: size.missing) })
    case "migrate":
        guard args.count >= 2, args.contains("--apply") else { throw CacheSSDError.message("A migração altera arquivos. Revise no aplicativo ou use migrate TOOL --apply [--release-local].") }
        let record = try MigrationEngine().migrate(toolID: args[1], removeLocal: args.contains("--release-local"), progress: { message in FileHandle.standardError.write(Data((message + "\n").utf8)) })
        try printJSON(record)
    case "restore":
        guard args.count >= 2, args.contains("--apply") else { throw CacheSSDError.message("Use restore TOOL --apply depois de revisar a cópia e o espaço disponível.") }
        try MigrationEngine().restore(toolID: args[1]); print("Cache restaurado.")
    case "prepare-cache":
        guard args.count >= 2, args.contains("--apply") else { throw CacheSSDError.message("Use prepare-cache TOOL --apply depois de revisar o destino para novas gravações.") }
        try printJSON(MigrationEngine().prepareFutureCache(toolID: args[1]))
    case "run":
        var values = Array(args.dropFirst()); if values.first == "--" { values.removeFirst() }
        guard let name = values.first else { throw CacheSSDError.message("Use CacheSSDHelper run -- comando argumentos") }
        let path = name.contains("/") ? URL(fileURLWithPath: name) : ToolLocator.locate(name)
        guard let executable = path else { throw CacheSSDError.message("Comando não encontrado.") }
        var environment = ProcessInfo.processInfo.environment
        let excluded = CacheRouter.commandExclusions(values)
        for (key,value) in CacheRouter.environment(settings: store.settings(), excluding: excluded) where environment[key] == nil { environment[key] = value }
        let child = Process(); child.executableURL = executable; child.arguments = Array(values.dropFirst()); child.environment = environment
        child.standardInput = FileHandle.standardInput; child.standardOutput = FileHandle.standardOutput; child.standardError = FileHandle.standardError
        try child.run(); child.waitUntilExit(); exit(child.terminationStatus)
    default:
        print("""
        CacheSSD Helper
          acceptance-check --workspace PASTA --output NOVO.json
                                       Verifica amostras isoladas; não atesta beta
          volumes                      Lista discos e espaço livre
          scan PASTA                   Analisa metadados; não altera arquivos
          index PASTA                  Indexa metadados em SQLite local
          search SESSION QUERY         Busca em todo o escopo indexado
          operations                   Lista registros duráveis de operação
          recover ID --apply           Recupera origem ausente sem sobrescrever
          resolve ID --apply           Encerra registro sem remover cópias
          inventory                    Mede caches locais e indica leituras incompletas
          status                       Mostra o destino de cada integração
          run -- COMANDO ARGUMENTOS    Executa com o cache compatível disponível
          migrate TOOL --apply         Copia e valida um cache selecionado
            --release-local            Libera a origem após validar a cópia
          restore TOOL --apply         Restaura uma cópia quando há espaço local
          prepare-cache TOOL --apply   Prepara SSD para um cache vazio ou ausente
        Ferramentas: \(CacheCatalog.all().map(\.id).joined(separator: ", ")).
        """)
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}

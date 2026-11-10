import SwiftUI
import AppKit
import CacheSSDCore

enum Palette {
    static let accent = Color(red: 39/255, green: 100/255, blue: 231/255)
    static let secondary = Color(red: 93/255, green: 148/255, blue: 1)
    static let orange = Color(red: 0.81, green: 0.39, blue: 0.17)
    static let panel = Color(nsColor: .controlBackgroundColor)
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 27)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 2) { Text("DiskWing").font(.system(size: 19, weight: .semibold)); Text("Espaço para o que importa").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 24)
                List(AppSection.allCases) { section in
                    Button { model.section = section } label: { HStack { Label(section.rawValue, systemImage: section.symbol); Spacer(minLength: 0) }.padding(.vertical, 7).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .listRowBackground(model.section == section ? Palette.accent.opacity(0.18) : Color.clear)
                        .accessibilityIdentifier("section-" + section.rawValue)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.selectedVolume?.name ?? "SSD desconectado", systemImage: model.selectedVolume == nil ? "externaldrive.badge.xmark" : "externaldrive.badge.checkmark")
                    Text("Processamento local · versão 0.1").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 215, ideal: 225, max: 260)
        } detail: {
            Group {
                switch model.section {
                case .overview: OverviewView()
                case .explorer: ExplorerView()
                case .caches: CachesView()
                case .history: HistoryView()
                case .preferences: PreferencesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = model.operationMessage {
                    HStack(spacing: 12) { ProgressView().controlSize(.small); Text(message); Spacer(); Text("Mantenha o SSD conectado").foregroundStyle(.secondary) }.font(.callout).padding(14).background(.bar)
                }
            }
            .toolbar {
                ToolbarItem { Button { model.chooseFolder() } label: { Label("Analisar pasta", systemImage: "folder.badge.plus") }.disabled(model.busy || model.isScanning).help("Escolher uma pasta para analisar, sem alterar arquivos") }
                ToolbarItem { Button { model.refreshVolumes() } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar os discos conectados") }
            }
        }
        .sheet(item: $model.review) { action in ReviewSheet(action: action).environmentObject(model) }
        .alert(model.errorMessage == nil ? "DiskWing" : "A operação não foi concluída", isPresented: Binding(get: { model.errorMessage != nil || model.notice != nil }, set: { if !$0 { model.errorMessage = nil; model.notice = nil } })) {
            Button("Entendi", role: .cancel) { model.errorMessage = nil; model.notice = nil }
        } message: { Text(model.errorMessage ?? model.notice ?? "") }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 28, weight: .semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                PageHeader(title: "Entenda o espaço do seu Mac.", subtitle: "Encontre o que ocupa espaço e revise suas opções antes de alterar qualquer arquivo.")
                ForEach(model.volumes) { volume in DriveView(volume: volume) }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Por onde começar").font(.title3.weight(.semibold))
                    HStack(spacing: 12) {
                        QuickScan(title: "Pasta pessoal", detail: "Uma visão dos seus arquivos", symbol: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                        QuickScan(title: "Downloads", detail: "Instaladores e arquivos baixados", symbol: "arrow.down.circle", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                        QuickScan(title: "Caches", detail: "Arquivos que podem ser recriados", symbol: "shippingbox", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 33, weight: .light)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("O SSD também pode receber caches.").font(.title3.weight(.semibold))
                        Text("Ferramentas compatíveis podem usar o disco externo nas novas execuções. Sem ele, os caches locais voltam a ser usados e podem precisar de novos downloads.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Explorar caches compatíveis") { model.section = .caches }
                    }
                    Spacer(minLength: 0)
                }
                if let report = model.report {
                    Button { model.section = .explorer } label: { HStack { Image(systemName: "clock"); Text("Retomar análise de \(report.root.name)"); Spacer(); Text(ByteText.format(report.root.logicalBytes)).foregroundStyle(.secondary); Image(systemName: "chevron.right") } }.buttonStyle(.plain).padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("O espaço livre vem do macOS. Os tamanhos de arquivos podem incluir blocos compartilhados; uma análise não é uma promessa de espaço recuperável.").font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

struct DriveView: View {
    let volume: VolumeInfo
    private var used: Int64 { max(0, volume.totalBytes - volume.freeBytes) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive").font(.title2).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) { Text(volume.name).font(.headline); Text(volume.isInternal ? "Armazenamento interno" : "Disco externo").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) { Text(ByteText.format(volume.freeBytes)).font(.system(size: 25, weight: .medium, design: .rounded)); Text("livres de \(ByteText.format(volume.totalBytes))").font(.caption).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) { Capsule().fill(Palette.accent.opacity(0.12)); Capsule().fill(volume.isInternal && volume.freeBytes < 10_000_000_000 ? Palette.orange : Palette.accent).frame(width: max(2, geometry.size.width * min(1, Double(used) / Double(max(1,volume.totalBytes))))) }
            }.frame(height: 10)
            HStack { Text("\(ByteText.format(used)) em uso"); Spacer(); if volume.isInternal && volume.freeBytes < 10_000_000_000 { Label("Pouco espaço disponível", systemImage: "exclamationmark.circle").foregroundStyle(Palette.orange) } else { Text(volume.isWritable ? "Disponível para gravação" : "Somente leitura") } }.font(.caption).foregroundStyle(.secondary)
        }.padding(21).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}

struct QuickScan: View {
    @EnvironmentObject var model: AppModel
    let title: String, detail: String, symbol: String
    let url: URL
    var body: some View {
        Button { model.scan(url) } label: {
            VStack(alignment: .leading, spacing: 9) { Image(systemName: symbol).font(.title2).foregroundStyle(Palette.accent); Text(title).font(.headline).foregroundStyle(.primary); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .top) }.frame(maxWidth: .infinity, alignment: .leading).padding(17).contentShape(Rectangle())
        }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).disabled(model.busy || model.isScanning)
    }
}

struct ExplorerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                PageHeader(title: "Explorar espaço", subtitle: "Os maiores itens aparecem primeiro. Abra uma pasta para entender seu conteúdo.")
                if model.isScanning {
                    HStack { ProgressView().controlSize(.small); VStack(alignment: .leading, spacing: 4) { Text("Lendo \(model.scanProgress?.entries.formatted() ?? "0") itens…").font(.headline); Text(model.scanProgress?.currentPath ?? "Preparando análise").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }; Spacer(); Button("Interromper") { model.cancel() } }.padding(13).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                if let report = model.report {
                    HStack(spacing: 22) {
                        Metric(label: "Tamanho encontrado", value: ByteText.format(report.root.logicalBytes))
                        Metric(label: "Blocos alocados apontados", value: ByteText.format(report.root.allocatedBytes))
                        Metric(label: "Arquivos lidos", value: report.root.fileCount.formatted())
                        Spacer()
                        Label(report.isPartial ? "Análise parcial" : "Análise concluída", systemImage: report.isPartial ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(report.isPartial ? Palette.orange : Palette.accent)
                    }
                }
            }.padding(28)
            if let report = model.report {
                HStack {
                    Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(model.breadcrumbs.count <= 1)
                    Text(model.currentFolder?.path ?? report.root.path).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Picker("Exibir", selection: $model.showLargest) { Text("Pastas e arquivos").tag(false); Text("Maiores arquivos").tag(true) }.pickerStyle(.segmented).frame(width: 280)
                    Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }.help("Exportar relatório com nomes e caminhos")
                }.padding(.horizontal, 24).padding(.bottom, 14)
                HSplitView {
                    VStack(spacing: 0) {
                        TextField("Buscar nesta lista", text: $model.search).textFieldStyle(.roundedBorder).padding(.horizontal, 18).padding(.bottom, 9)
                        Table(model.visibleItems, selection: $model.selectedPath) {
                            TableColumn("Nome") { item in
                                HStack(spacing: 9) { Image(systemName: item.isSymbolicLink ? "link" : item.isDirectory ? "folder.fill" : "doc").foregroundStyle(item.isDirectory ? Palette.secondary : .secondary); VStack(alignment: .leading, spacing: 3) { Text(item.name).lineLimit(1); if let issue = item.issue { Text(issue).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } } }.padding(.vertical, 4).onTapGesture(count: 2) { model.openFolder(item) }.contextMenu { ItemMenu(item: item) }
                            }.width(min: 150, ideal: 300)
                            TableColumn("Tamanho") { item in Text(item.issue?.hasPrefix("Sem acesso") == true ? "Não lido" : ByteText.format(item.logicalBytes)).monospacedDigit().foregroundStyle(item.logicalBytes > 0 ? .primary : .secondary) }.width(95)
                            TableColumn("Categoria") { item in Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 150)
                        }
                        .contextMenu(forSelectionType: String.self) { paths in
                            if let path = paths.first, let item = model.visibleItems.first(where: { $0.path == path }) { ItemMenu(item: item) }
                        } primaryAction: { paths in
                            if let path = paths.first, let item = model.visibleItems.first(where: { $0.path == path }), !model.busy, !model.isScanning { model.openFolder(item) }
                        }
                    }.frame(minWidth: 460)
                    InspectorView(item: model.selectedItem).frame(minWidth: 235, idealWidth: 265, maxWidth: 310)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let issue = model.currentFolder?.issue { Text(issue).foregroundStyle(Palette.orange) }
                    if !report.unreadablePaths.isEmpty { Text("\(report.unreadablePaths.count) áreas ou itens não puderam ser lidos. Esses tamanhos são desconhecidos.").foregroundStyle(Palette.orange) }
                    Text("Blocos APFS podem ser compartilhados. Links e outros volumes não são percorridos. Uma análise tem limite de 200 mil itens; analise subpastas para aprofundar.").foregroundStyle(.secondary)
                }.font(.caption).padding(16)
            } else if !model.isScanning {
                ContentUnavailableView { Label("Escolha por onde começar", systemImage: "folder") } description: { Text("A análise encontra arquivos grandes sem alterar seus dados.") } actions: { Button("Escolher pasta…") { model.chooseFolder() }.buttonStyle(.borderedProminent) }
            } else { Spacer() }
        }
    }
}

struct Metric: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 21, weight: .medium, design: .rounded)); Text(label).font(.caption).foregroundStyle(.secondary) } }
}

struct ItemMenu: View {
    @EnvironmentObject var model: AppModel
    let item: ScanItem
    var body: some View {
        Button("Mostrar no Finder") { model.showInFinder(item) }
        if item.isDirectory { Button("Analisar esta pasta") { model.scan(item.url) }.disabled(model.isScanning || model.busy) }
        Divider()
        Button("Revisar movimentação…") { model.reviewMove(item) }.disabled(PersonalActionPolicy.reasonPreventing(item.url) != nil || model.busy || model.isScanning)
        Button("Revisar envio à Lixeira…") { model.review = .trash(item) }.disabled(PersonalActionPolicy.reasonPreventing(item.url) != nil || model.busy || model.isScanning)
    }
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    let item: ScanItem?
    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: item.isDirectory ? "folder" : "doc").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    Text(item.name).font(.headline).textSelection(.enabled)
                    Text(ByteText.format(item.logicalBytes)).font(.system(size: 25, weight: .medium, design: .rounded))
                    Text(item.category.rawValue).foregroundStyle(.secondary)
                    Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    if let reason = PersonalActionPolicy.reasonPreventing(item.url) { Text(reason).font(.callout).foregroundStyle(.secondary) }
                    else { Text("Revise o conteúdo antes de escolher uma ação. O tamanho não indica se um arquivo é dispensável.").font(.callout).foregroundStyle(.secondary) }
                    Button("Mostrar no Finder") { model.showInFinder(item) }.frame(maxWidth: .infinity, alignment: .leading)
                    if item.isDirectory {
                        Button("Abrir pasta") { model.openFolder(item) }.disabled(model.isScanning || model.busy)
                        Button("Analisar esta pasta") { model.scan(item.url) }.disabled(model.isScanning || model.busy)
                    }
                    if PersonalActionPolicy.reasonPreventing(item.url) == nil {
                        Button("Revisar movimentação…") { model.reviewMove(item) }.disabled(model.busy || model.isScanning)
                        Button("Revisar envio à Lixeira…") { model.review = .trash(item) }.disabled(model.busy || model.isScanning)
                    }
                    if item.category == .cache || item.category == .developer { Button("Ver integrações de cache") { model.section = .caches } }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            } else { VStack(spacing: 12) { Image(systemName: "sidebar.right").font(.largeTitle).foregroundStyle(.tertiary); Text("Selecione um item para ver detalhes e ações.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(28).frame(maxWidth: .infinity) }
        }.background(Palette.panel)
    }
}

struct CachesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                PageHeader(title: "Caches e SSD", subtitle: "Migre arquivos recriáveis de ferramentas compatíveis, com conferência antes de liberar a origem.")
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("Disco de destino").font(.headline); Text("Sem o disco, novas execuções usam o cache local.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Picker("SSD", selection: Binding(get: { model.settings.selectedVolumeUUID ?? "" }, set: { model.settings.selectedVolumeUUID = $0.isEmpty ? nil : $0; model.saveSettings() })) {
                        Text("Escolher disco…").tag("")
                        ForEach(model.volumes.filter { !$0.isInternal }) { volume in Text("\(volume.name) — \(ByteText.format(volume.freeBytes)) livres").tag(volume.uuid) }
                        if let uuid = model.settings.selectedVolumeUUID, !model.volumes.contains(where: { $0.uuid == uuid }) { Text("Disco desconectado").tag(uuid) }
                    }.frame(maxWidth: 330).disabled(model.busy)
                }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Label(model.settings.shellIntegrationEnabled ? "Integração com o terminal ativada" : "Integração com o terminal ainda não ativada", systemImage: model.settings.shellIntegrationEnabled ? "checkmark.circle" : "terminal").font(.callout)
                    Spacer()
                    if !model.settings.shellIntegrationEnabled { Button("Revisar integração…") { model.review = .integration }.disabled(model.busy) }
                    else { Toggle("Usar SSD nas novas execuções", isOn: $model.settings.useExternal).onChange(of: model.settings.useExternal) { model.saveSettings() }.toggleStyle(.switch).controlSize(.small).disabled(model.busy) }
                }
                HStack {
                    Text("\(ByteText.format(model.candidates)) encontrados nos caches locais").font(.title3.weight(.semibold))
                    Spacer()
                    if model.inventoryRunning { ProgressView().controlSize(.small); Text("Medindo…").font(.caption).foregroundStyle(.secondary) }
                    Button("Medir novamente") { model.refreshInventory() }.disabled(model.inventoryRunning || model.busy)
                }
                VStack(spacing: 0) {
                    ForEach(model.tools) { tool in
                        CacheRow(tool: tool)
                        if tool.id != model.tools.last?.id { Divider().padding(.leading, 18) }
                    }
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
                HStack(alignment: .top, spacing: 12) { Image(systemName: "info.circle").foregroundStyle(Palette.accent); Text("O Chrome, seus perfis, cookies e senhas ficam fora da migração. SDKs, emuladores, projetos e executáveis de serviços também permanecem no local atual. Aplicativos abertos pelo Dock usam suas próprias configurações; esta integração cobre o terminal e o executor do DiskWing.").font(.callout).foregroundStyle(.secondary) }
                Text("Cópias de recuperação ficam no SSD. Ao voltar ao Mac, caches vazios podem exigir downloads e tornar o primeiro uso mais lento. A desconexão física durante uma operação pode interrompê-la.").font(.caption).foregroundStyle(.secondary)
                if let volume = model.selectedVolume { Button("Preparar para ejetar \(volume.name)…") { model.review = .eject(volume) }.disabled(model.busy || model.isScanning) }
            }.padding(30)
        }.onAppear { if model.toolSizes.isEmpty { model.refreshInventory() } }
    }
}

struct CacheRow: View {
    @EnvironmentObject var model: AppModel
    let tool: CacheDescriptor
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "shippingbox").font(.title2.weight(.light)).foregroundStyle(Palette.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(tool.name).font(.headline); if model.settings.locations[tool.id] != nil { Text(model.settings.shellIntegrationEnabled ? "Cópia no SSD" : "Migrado; integração pendente").font(.caption).foregroundStyle(Palette.accent) } }
                Text(tool.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(tool.source.path).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(model.toolSizes[tool.id].map { ByteText.format($0.logical) } ?? "—").font(.callout.weight(.medium)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Menu {
                Button("Revisar migração…") { model.review = .migration(tool) }.disabled(model.selectedVolume == nil || (model.toolSizes[tool.id]?.logical ?? 0) == 0)
                Button("Mostrar cache local") { NSWorkspace.shared.activateFileViewerSelecting([tool.source]) }
                if model.settings.locations[tool.id] != nil { Button("Restaurar cópia ao Mac…") { model.review = .restore(tool) } }
            } label: { Text("Ações") }.menuStyle(.borderlessButton).frame(width: 75).disabled(model.busy || model.isScanning)
        }.padding(18)
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Histórico", subtitle: "Operações realizadas neste Mac, com o resultado e o local de recuperação quando disponível.")
            if !model.interrupted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(model.interrupted.count) registros de migração incompleta", systemImage: "exclamationmark.circle").foregroundStyle(Palette.orange).font(.headline)
                    ForEach(model.interrupted.prefix(5)) { journal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(journal.toolID): \(journal.detail)").font(.callout)
                            if let path = journal.localQuarantine, FileManager.default.fileExists(atPath: path) { Button("Mostrar origem preservada") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.font(.caption) }
                        }
                    }
                    Button("Abrir registros de recuperação") { NSWorkspace.shared.open(model.store.base) }
                }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.history.isEmpty { ContentUnavailableView("Nenhuma operação realizada", systemImage: "clock", description: Text("Analisar espaço não move nem apaga seus arquivos.")) }
            else {
                List(model.history) { record in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(record.title).font(.headline); Spacer(); Text(record.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        Text(record.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        if let delta = record.measuredFreeDelta { Text("Variação observada do espaço livre: \(delta >= 0 ? "+" : "−")\(ByteText.format(abs(delta)))").font(.caption).foregroundStyle(Palette.accent) }
                        if let path = record.recoveryPath { Button("Mostrar local de recuperação") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.font(.caption) }
                    }.padding(.vertical, 10)
                }.listStyle(.inset)
            }
            Text("A variação de espaço livre inclui a atividade de outros aplicativos. Arquivos na Lixeira ainda ocupam espaço.").font(.caption).foregroundStyle(.secondary)
        }.padding(30)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                PageHeader(title: "Ajustes", subtitle: "Controle como o DiskWing acompanha suas ferramentas e armazena os próprios registros.")
                GroupBox("Inicialização") {
                    Toggle("Abrir DiskWing ao iniciar a sessão", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).padding(10)
                }
                GroupBox("Integração com o terminal") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cada comando escolhe o cache disponível naquele momento. Preferências personalizadas têm prioridade. Programas já abertos mantêm seu ambiente até serem reabertos.").foregroundStyle(.secondary)
                        HStack {
                            Button("Revisar integração…") { model.review = .integration }
                            if model.settings.shellIntegrationEnabled { Button("Desativar integração…") { model.review = .disableIntegration } }
                        }
                        Text("O executor também está no aplicativo: CacheSSDHelper run -- comando argumentos.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(10)
                }
                GroupBox("Privacidade e permissões") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nomes, tamanhos e histórico ficam neste Mac. Nenhuma análise é enviada a um servidor. Relatórios só são exportados quando você escolhe um destino.")
                        Text("Sem permissão para uma área, o resultado é marcado como parcial. Conceda Acesso Total ao Disco nos ajustes do macOS somente se precisar ampliar a análise.").foregroundStyle(.secondary)
                        Button("Abrir Privacidade e Segurança") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                    }.padding(10)
                }
                GroupBox("Arquivos de compilação do Xcode") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Se o Xcode já aponta Derived Data para o SSD, é possível voltar ao local padrão do Mac. A cópia existente no SSD fica preservada. Encerre o Xcode antes de alterar.").foregroundStyle(.secondary)
                        Button("Revisar retorno ao local padrão…") { model.review = .xcodeLocal }.disabled(model.busy)
                    }.padding(10)
                }
                GroupBox("Registros e recuperação") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("São mantidas até 150 operações e 50 resumos de análise. A árvore completa só permanece na memória durante o uso; nenhuma indexação contínua é executada.").foregroundStyle(.secondary)
                        Button("Mostrar registros locais") { NSWorkspace.shared.open(model.store.base) }
                        Text("Versão local 0.1.0. Distribuição pública, notarização e validação com outras pessoas ainda não foram concluídas.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
            }.padding(30)
        }
    }
}

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let action: ReviewAction
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(action.title, systemImage: symbol).font(.title2.weight(.semibold))
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch action {
            case .migration(let tool):
                fact("Ferramenta", tool.name)
                fact("Origem", tool.source.path)
                fact("Destino", model.selectedVolume?.name ?? "SSD não conectado")
                fact("Tamanho encontrado", ByteText.format(model.toolSizes[tool.id]?.logical ?? 0))
                Toggle("Liberar o cache local após copiar e validar", isOn: Binding(get: { tool.canReleaseLocal && model.releaseLocal }, set: { model.releaseLocal = $0 })).disabled(!tool.canReleaseLocal)
                if !tool.canReleaseLocal { Text("Nesta versão, a origem de \(tool.name) é mantida porque instalações existentes podem depender de links para esse cache. A cópia no SSD atende novas execuções compatíveis.").font(.caption).foregroundStyle(Palette.orange) }
                Text("Feche a ferramenta antes de continuar. Sem SSD, os caches podem ser baixados novamente. Os executáveis locais do npx não são removidos.").font(.caption).foregroundStyle(.secondary)
            case .trash(let item): fact("Item", item.path); fact("Tamanho encontrado", ByteText.format(item.logicalBytes)); Text("A Lixeira não será esvaziada pelo aplicativo.").font(.caption).foregroundStyle(.secondary)
            case .move(let item, let destination): fact("Origem", item.path); fact("Pasta de destino", destination.path); Text("A cópia ficará no destino e a origem na Lixeira. Só esvazie a Lixeira depois de revisar a cópia. Se o destino for externo, o arquivo dependerá dele para ser acessado.").font(.caption).foregroundStyle(.secondary)
            case .integration: fact("Arquivo atualizado", "Configuração do terminal zsh"); Text("Uma cópia da configuração atual ficará nos registros do DiskWing. A linha conhecida que envia temporários ao PortableSSD será substituída pelo local padrão do macOS. Abra um novo terminal após ativar.").font(.callout)
            case .disableIntegration: Text("Abra um novo terminal após desativar. Caches existentes e cópias no SSD serão preservados.")
            case .restore(let tool): fact("Ferramenta", tool.name); Text("A restauração só ocorre se houver espaço no Mac e o cache local estiver vazio. A cópia no SSD será mantida.")
            case .eject(let volume): fact("Disco", volume.name); Text("Novas execuções passam a usar o Mac. Se houver arquivos abertos, a ejeção será adiada. Outros aplicativos também podem impedir a ejeção pelo macOS.")
            case .xcodeLocal: Text("Uma cópia das preferências de Derived Data ficará nos registros locais. O Xcode usará a pasta padrão do armazenamento interno. Nada será apagado no SSD.")
            }
            Divider()
            HStack { Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(action.title) { model.execute(action) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 560)
    }
    private func fact(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
    private var symbol: String { switch action { case .trash: return "trash"; case .eject: return "eject.circle"; case .integration, .disableIntegration: return "terminal"; default: return "externaldrive.badge.checkmark" } }
    private var description: String {
        switch action {
        case .migration: return "Confira a origem e o destino. A migração copia o conteúdo, verifica sua integridade e valida a ferramenta antes de liberar a origem."
        case .trash: return "Este item será enviado à Lixeira do macOS. Revise seu conteúdo antes de confirmar."
        case .move: return "O aplicativo confere a cópia antes de enviar a origem à Lixeira. Nada existente no destino será sobrescrito."
        case .integration: return "Ative o direcionamento nas novas execuções do terminal. A ausência do SSD devolve os padrões locais."
        case .disableIntegration: return "Remova a integração dos novos terminais e volte a usar os caches locais."
        case .restore: return "Recupere uma cópia do cache para o armazenamento interno."
        case .eject: return "Prepare o retorno aos caches locais antes de desconectar o SSD."
        case .xcodeLocal: return "Restabeleça o destino local dos arquivos recriáveis de compilação do Xcode."
        }
    }
}

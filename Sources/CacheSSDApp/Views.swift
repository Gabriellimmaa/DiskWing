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
                    VStack(alignment: .leading, spacing: 2) { Text("DiskWing").font(.system(size: 19, weight: .semibold)); Text(L10n.text("Espaço para o que importa")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 24)
                List(AppSection.allCases) { section in
                    Button { model.section = section } label: { HStack { Label(L10n.message(section.rawValue), systemImage: section.symbol); Spacer(minLength: 0) }.padding(.vertical, 7).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .listRowBackground(model.section == section ? Palette.accent.opacity(0.18) : Color.clear)
                        .accessibilityIdentifier("section-" + section.rawValue)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.selectedVolume?.name ?? L10n.text("SSD desconectado"), systemImage: model.selectedVolume == nil ? "externaldrive.badge.xmark" : "externaldrive.badge.checkmark")
                    Text(L10n.text("Processamento local · prévia de desenvolvimento")).font(.caption).foregroundStyle(.secondary)
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
                    HStack(spacing: 12) { ProgressView().controlSize(.small); Text(L10n.message(message)); Spacer(); Text(L10n.text("Mantenha o SSD conectado")).foregroundStyle(.secondary); Button(L10n.text("Cancelar operação")) { model.cancel() } }.font(.callout).padding(14).background(.bar)
                }
            }
            .toolbar {
                ToolbarItem { Button { model.chooseFolder() } label: { Label(L10n.text("Analisar pasta"), systemImage: "folder.badge.plus") }.disabled(model.busy || model.isScanning).help(L10n.text("Escolher uma pasta para analisar, sem alterar arquivos")) }
                ToolbarItem { Button { model.refreshVolumes() } label: { Image(systemName: "arrow.clockwise") }.help(L10n.text("Atualizar os discos conectados")).accessibilityLabel(L10n.text("Atualizar os discos conectados")) }
            }
        }
        .sheet(item: $model.review) { action in ReviewSheet(action: action).environmentObject(model) }
        .alert(model.errorMessage == nil ? "DiskWing" : L10n.text("A operação não foi concluída"), isPresented: Binding(get: { model.errorMessage != nil || model.notice != nil }, set: { if !$0 { model.errorMessage = nil; model.notice = nil } })) {
            Button(L10n.text("Entendi"), role: .cancel) { model.errorMessage = nil; model.notice = nil }
        } message: { Text(L10n.message(model.errorMessage ?? model.notice ?? "")) }
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
                PageHeader(title: L10n.text("Entenda o espaço do seu Mac."), subtitle: L10n.text("Encontre o que ocupa espaço e revise suas opções antes de alterar qualquer arquivo."))
                ForEach(model.volumes) { volume in DriveView(volume: volume) }
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Por onde começar")).font(.title3.weight(.semibold))
                    HStack(spacing: 12) {
                        QuickScan(title: L10n.text("Pasta pessoal"), detail: L10n.text("Uma visão dos seus arquivos"), symbol: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                        QuickScan(title: L10n.text("Downloads"), detail: L10n.text("Instaladores e arquivos baixados"), symbol: "arrow.down.circle", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                        QuickScan(title: L10n.text("Caches"), detail: L10n.text("Arquivos que podem ser recriados"), symbol: "shippingbox", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 33, weight: .light)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("O SSD também pode receber caches.")).font(.title3.weight(.semibold))
                        Text(L10n.text("Ferramentas compatíveis podem usar o disco externo nas novas execuções. Sem ele, os caches locais voltam a ser usados e podem precisar de novos downloads.")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L10n.text("Explorar caches compatíveis")) { model.section = .caches }
                    }
                    Spacer(minLength: 0)
                }
                if let report = model.report {
                    Button { model.section = .explorer } label: { HStack { Image(systemName: "clock"); Text(L10n.text("Retomar análise de \(report.root.name)")); Spacer(); Text(ByteText.format(report.root.logicalBytes)).foregroundStyle(.secondary); Image(systemName: "chevron.right") } }.buttonStyle(.plain).padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Text(L10n.text("O espaço livre vem do macOS. Os tamanhos de arquivos podem incluir blocos compartilhados; uma análise não é uma promessa de espaço recuperável.")).font(.caption).foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 3) { Text(volume.name).font(.headline); Text(volume.isInternal ? L10n.text("Armazenamento interno") : L10n.text("Disco externo")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) { Text(ByteText.format(volume.freeBytes)).font(.system(size: 25, weight: .medium, design: .rounded)); Text(L10n.text("livres de \(ByteText.format(volume.totalBytes))")).font(.caption).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) { Capsule().fill(Palette.accent.opacity(0.12)); Capsule().fill(volume.isInternal && volume.freeBytes < 10_000_000_000 ? Palette.orange : Palette.accent).frame(width: max(2, geometry.size.width * min(1, Double(used) / Double(max(1,volume.totalBytes))))) }
            }.frame(height: 10)
            HStack { Text(L10n.text("\(ByteText.format(used)) em uso")); Spacer(); if volume.isInternal && volume.freeBytes < 10_000_000_000 { Label(L10n.text("Pouco espaço disponível"), systemImage: "exclamationmark.circle").foregroundStyle(Palette.orange) } else { Text(volume.isWritable ? L10n.text("Disponível para gravação") : L10n.text("Somente leitura")) } }.font(.caption).foregroundStyle(.secondary)
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
                PageHeader(title: L10n.text("Explorar espaço"), subtitle: L10n.text("Os maiores itens aparecem primeiro. Abra uma pasta para entender seu conteúdo."))
                if model.isScanning {
                    HStack { ProgressView().controlSize(.small); VStack(alignment: .leading, spacing: 4) { Text(L10n.text("Lendo \(model.scanProgress?.entries.formatted(.number.locale(L10n.locale)) ?? "0") itens…")).font(.headline); Text(model.scanProgress?.currentPath ?? L10n.text("Preparando análise")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }; Spacer(); Button(L10n.text("Interromper")) { model.cancel() } }.padding(13).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                if let report = model.report {
                    HStack(spacing: 22) {
                        Metric(label: L10n.text("Tamanho encontrado"), value: ByteText.format(report.root.logicalBytes))
                        Metric(label: L10n.text("Blocos alocados apontados"), value: ByteText.format(report.root.allocatedBytes))
                        Metric(label: L10n.text("Arquivos lidos"), value: report.root.fileCount.formatted(.number.locale(L10n.locale)))
                        Spacer()
                        Label(report.isPartial ? L10n.text("Análise parcial") : L10n.text("Análise concluída"), systemImage: report.isPartial ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(report.isPartial ? Palette.orange : Palette.accent)
                    }
                }
            }.padding(28)
            if let report = model.report {
                HStack {
                    Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(model.breadcrumbs.count <= 1).accessibilityLabel(L10n.text("Voltar à pasta anterior"))
                    Text(model.currentFolder?.path ?? report.root.path).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Picker(L10n.text("Exibir"), selection: $model.showLargest) { Text(L10n.text("Pastas e arquivos")).tag(false); Text(L10n.text("Maiores arquivos")).tag(true) }.pickerStyle(.segmented).frame(width: 280)
                    Toggle(L10n.text("Acompanhar pasta"), isOn: Binding(get: { model.isWatchingCurrentRoot }, set: { model.watchCurrentRoot($0) })).toggleStyle(.checkbox)
                    Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }.help(L10n.text("Exportar relatório com nomes e caminhos")).accessibilityLabel(L10n.text("Exportar relatório com nomes e caminhos")).disabled(model.busy || model.isScanning)
                }.padding(.horizontal, 24).padding(.bottom, 14)
                HSplitView {
                    VStack(spacing: 0) {
                        HStack {
                            TextField(L10n.text("Buscar em toda a análise"), text: $model.search).textFieldStyle(.roundedBorder)
                            TextField(L10n.text("Mínimo MiB"), text: $model.minimumMiB).textFieldStyle(.roundedBorder).frame(width: 105)
                            Toggle(L10n.text("Ordenar por blocos"), isOn: $model.allocatedOrder).toggleStyle(.checkbox).font(.caption)
                        }.padding(.horizontal, 18).padding(.bottom, 9)
                        HStack {
                            Button(L10n.text("Anterior")) { model.previousPage() }.disabled(model.indexOffset == 0 || model.indexLoading)
                            Text(L10n.text("\(model.indexTotal == 0 ? 0 : model.indexOffset + 1)–\(min(model.indexTotal, model.indexOffset + model.indexedItems.count)) de \(model.indexTotal)")).font(.caption).monospacedDigit()
                            if model.indexLoading { ProgressView().controlSize(.mini) }
                            Spacer()
                            Button(L10n.text("Próxima")) { model.nextPage() }.disabled(model.indexOffset + model.indexedItems.count >= model.indexTotal || model.indexLoading)
                        }.padding(.horizontal, 18).padding(.bottom, 8)
                        Table(model.visibleItems, selection: $model.selectedPath) {
                            TableColumn(L10n.text("Nome")) { item in
                                HStack(spacing: 9) { Image(systemName: item.isSymbolicLink ? "link" : item.isDirectory ? "folder.fill" : "doc").foregroundStyle(item.isDirectory ? Palette.secondary : .secondary); VStack(alignment: .leading, spacing: 3) { Text(item.name).lineLimit(1); if let issue = item.issue { Text(L10n.message(issue)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } } }.padding(.vertical, 4).onTapGesture(count: 2) { model.openFolder(item) }.contextMenu { ItemMenu(item: item) }
                            }.width(min: 150, ideal: 300)
                            TableColumn(L10n.text("Tamanho")) { item in Text(item.issue?.hasPrefix("Sem acesso") == true ? L10n.text("Não lido") : ByteText.format(item.logicalBytes)).monospacedDigit().foregroundStyle(item.logicalBytes > 0 ? .primary : .secondary) }.width(95)
                            TableColumn(L10n.text("Categoria")) { item in Text(L10n.message(item.category.rawValue)).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 150)
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
                    if let issue = model.currentFolder?.issue { Text(L10n.message(issue)).foregroundStyle(Palette.orange) }
                    if !report.unreadablePaths.isEmpty { Text(L10n.text("\(report.unreadablePaths.count) áreas ou itens não puderam ser lidos. Esses tamanhos são desconhecidos.")).foregroundStyle(Palette.orange) }
                    Text(L10n.text("Blocos APFS podem ser compartilhados. Links e outros volumes não são percorridos. O índice limita itens, profundidade e espaço; análises parciais indicam quando aprofundar em uma subpasta.")).foregroundStyle(.secondary)
                }.font(.caption).padding(16)
            } else if !model.isScanning {
                ContentUnavailableView { Label(L10n.text("Escolha por onde começar"), systemImage: "folder") } description: { Text(L10n.text("A análise encontra arquivos grandes sem alterar seus dados.")) } actions: { Button(L10n.text("Escolher pasta…")) { model.chooseFolder() }.buttonStyle(.borderedProminent) }
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
        Button(L10n.text("Mostrar no Finder")) { model.showInFinder(item) }
        if item.isDirectory { Button(L10n.text("Analisar esta pasta")) { model.scan(item.url) }.disabled(model.isScanning || model.busy) }
        Divider()
        Button(L10n.text("Revisar movimentação…")) { model.reviewMove(item) }.disabled(PersonalActionPolicy.reasonPreventing(item.url) != nil || model.busy || model.isScanning)
        Button(L10n.text("Revisar envio à Lixeira…")) { model.review = .trash(item) }.disabled(PersonalActionPolicy.reasonPreventing(item.url) != nil || model.busy || model.isScanning)
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
                    Text(L10n.message(item.category.rawValue)).foregroundStyle(.secondary)
                    Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    if let reason = PersonalActionPolicy.reasonPreventing(item.url) { Text(L10n.message(reason)).font(.callout).foregroundStyle(.secondary) }
                    else { Text(L10n.text("Revise o conteúdo antes de escolher uma ação. O tamanho não indica se um arquivo é dispensável.")).font(.callout).foregroundStyle(.secondary) }
                    Button(L10n.text("Mostrar no Finder")) { model.showInFinder(item) }.frame(maxWidth: .infinity, alignment: .leading)
                    if item.isDirectory {
                        Button(L10n.text("Abrir pasta")) { model.openFolder(item) }.disabled(model.isScanning || model.busy)
                        Button(L10n.text("Analisar esta pasta")) { model.scan(item.url) }.disabled(model.isScanning || model.busy)
                    }
                    if PersonalActionPolicy.reasonPreventing(item.url) == nil {
                        Button(L10n.text("Revisar movimentação…")) { model.reviewMove(item) }.disabled(model.busy || model.isScanning)
                        Button(L10n.text("Revisar envio à Lixeira…")) { model.review = .trash(item) }.disabled(model.busy || model.isScanning)
                    }
                    if item.category == .cache || item.category == .developer { Button(L10n.text("Ver integrações de cache")) { model.section = .caches } }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            } else { VStack(spacing: 12) { Image(systemName: "sidebar.right").font(.largeTitle).foregroundStyle(.tertiary); Text(L10n.text("Selecione um item para ver detalhes e ações.")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(28).frame(maxWidth: .infinity) }
        }.background(Palette.panel)
    }
}

struct CachesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                PageHeader(title: L10n.text("Caches e SSD"), subtitle: L10n.text("Migre arquivos recriáveis de ferramentas compatíveis, com conferência antes de liberar a origem."))
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(L10n.text("Disco de destino")).font(.headline); Text(L10n.text("Sem o disco, novas execuções usam o cache local.")).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Picker("SSD", selection: Binding(get: { model.settings.selectedVolumeUUID ?? "" }, set: { model.settings.selectedVolumeUUID = $0.isEmpty ? nil : $0; model.saveSettings() })) {
                        Text(L10n.text("Escolher disco…")).tag("")
                        ForEach(model.volumes.filter { !$0.isInternal }) { volume in Text(L10n.text("\(volume.name) — \(ByteText.format(volume.freeBytes)) livres")).tag(volume.uuid) }
                        if let uuid = model.settings.selectedVolumeUUID, !model.volumes.contains(where: { $0.uuid == uuid }) { Text(L10n.text("Disco desconectado")).tag(uuid) }
                    }.frame(maxWidth: 330).disabled(model.busy)
                }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Label(model.settings.shellIntegrationEnabled ? L10n.text("Integração com o terminal ativada") : L10n.text("Integração com o terminal ainda não ativada"), systemImage: model.settings.shellIntegrationEnabled ? "checkmark.circle" : "terminal").font(.callout)
                    Spacer()
                    if !model.settings.shellIntegrationEnabled { Button(L10n.text("Revisar integração…")) { model.review = .integration }.disabled(model.busy) }
                    else { Toggle(L10n.text("Usar SSD nas novas execuções"), isOn: $model.settings.useExternal).onChange(of: model.settings.useExternal) { model.saveSettings() }.toggleStyle(.switch).controlSize(.small).disabled(model.busy) }
                }
                HStack {
                    Text(L10n.text("\(ByteText.format(model.candidates)) encontrados nos caches locais")).font(.title3.weight(.semibold))
                    Spacer()
                    if model.inventoryRunning { ProgressView().controlSize(.small); Text(L10n.text("Medindo…")).font(.caption).foregroundStyle(.secondary) }
                    Button(L10n.text("Medir novamente")) { model.refreshInventory() }.disabled(model.inventoryRunning || model.busy)
                }
                VStack(spacing: 0) {
                    ForEach(model.tools) { tool in
                        CacheRow(tool: tool)
                        if tool.id != model.tools.last?.id { Divider().padding(.leading, 18) }
                    }
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
                HStack(alignment: .top, spacing: 12) { Image(systemName: "info.circle").foregroundStyle(Palette.accent); Text(L10n.text("O Chrome, seus perfis, cookies e senhas ficam fora da migração. SDKs, emuladores, projetos e executáveis de serviços também permanecem no local atual. Aplicativos abertos pelo Dock usam suas próprias configurações; esta integração cobre o terminal e o executor do DiskWing.")).font(.callout).foregroundStyle(.secondary) }
                Text(L10n.text("Cópias de recuperação ficam no SSD. Ao voltar ao Mac, caches vazios podem exigir downloads e tornar o primeiro uso mais lento. A desconexão física durante uma operação pode interrompê-la.")).font(.caption).foregroundStyle(.secondary)
                if let volume = model.selectedVolume { Button(L10n.text("Preparar para ejetar \(volume.name)…")) { model.review = .eject(volume) }.disabled(model.busy || model.isScanning) }
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
                HStack { Text(tool.name).font(.headline); if model.settings.locations[tool.id] != nil { Text(model.settings.shellIntegrationEnabled ? L10n.text("Cópia no SSD") : L10n.text("Migrado; integração pendente")).font(.caption).foregroundStyle(Palette.accent) } }
                Text(L10n.message(tool.explanation)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let adapter = model.adapterStatuses[tool.id] {
                    Text(L10n.message(adapter.explanation)).font(.caption).foregroundStyle(.secondary)
                    if let version = adapter.version { Text(L10n.text("Versão identificada: \(version)")).font(.caption2).foregroundStyle(.secondary) }
                    if let path = adapter.effectiveCachePath { Text(path).font(.caption2).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                }
                Text(tool.source.path).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(model.toolSizes[tool.id].map { $0.missing ? L10n.text("Ausente") : !$0.complete ? L10n.text("Desconhecido") : ByteText.format($0.logical) } ?? L10n.text("—")).font(.callout.weight(.medium)).monospacedDigit().frame(width: 100, alignment: .trailing)
            Menu {
                Button(L10n.text("Revisar migração…")) { model.review = .migration(tool) }.disabled(model.selectedVolume == nil || (model.toolSizes[tool.id]?.logical ?? 0) == 0 || model.toolSizes[tool.id]?.complete != true || model.adapterStatuses[tool.id]?.state != "native-available")
                Button(L10n.text("Mostrar cache local")) { NSWorkspace.shared.activateFileViewerSelecting([tool.source]) }
                if model.settings.locations[tool.id] != nil { Button(L10n.text("Restaurar cópia ao Mac…")) { model.review = .restore(tool) } }
            } label: { Text(L10n.text("Ações")) }.menuStyle(.borderlessButton).frame(width: 75).disabled(model.busy || model.isScanning)
        }.padding(18)
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: L10n.text("Histórico"), subtitle: L10n.text("Operações realizadas neste Mac, com o resultado e o local de recuperação quando disponível."))
            if !model.store.unreadableOperationRecords().isEmpty || !model.store.pendingConfigurationRecords().isEmpty {
                Label(L10n.text("Há registros de recuperação ou configuração pendentes. Eles foram preservados; abra os registros locais para revisão."), systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
                Button(L10n.text("Mostrar registros locais")) { NSWorkspace.shared.open(model.store.base) }
            }
            if !model.recoveries.isEmpty {
                ForEach(model.recoveries) { assessment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(assessment.journal.kind).font(.headline)
                        Text(L10n.message(assessment.explanation)).font(.callout)
                        Text(assessment.journal.source).font(.caption).textSelection(.enabled)
                        HStack {
                            if assessment.canRestoreSource { Button(L10n.text("Revisar recuperação…")) { model.review = .recover(assessment) } }
                            Button(L10n.text("Revisar encerramento…")) { model.review = .resolve(assessment) }
                        }
                    }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if !model.interrupted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.text("\(model.interrupted.count) registros de migração incompleta"), systemImage: "exclamationmark.circle").foregroundStyle(Palette.orange).font(.headline)
                    ForEach(model.interrupted.prefix(5)) { journal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text("\(journal.toolID): \(journal.detail)")).font(.callout)
                            if let path = journal.localQuarantine, FileManager.default.fileExists(atPath: path) { Button(L10n.text("Mostrar origem preservada")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.font(.caption) }
                        }
                    }
                    Button(L10n.text("Abrir registros de recuperação")) { NSWorkspace.shared.open(model.store.base) }
                }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            if let comparison = model.growthComparison {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L10n.text("Comparar com"), selection: $model.growthDays) {
                        Text(L10n.text("Análise anterior")).tag(0); Text(L10n.text("7 dias")).tag(7); Text(L10n.text("30 dias")).tag(30)
                    }.frame(maxWidth: 340)
                    if let delta = comparison.logicalDelta {
                        Text(L10n.text("Variação nos arquivos: \(delta >= 0 ? "+" : "−")\(ByteText.format(abs(delta)))")).font(.headline)
                        ForEach(comparison.folders.prefix(8)) { item in
                            HStack { Text(URL(fileURLWithPath: item.path).lastPathComponent); Spacer(); Text("\(item.logicalDelta >= 0 ? "+" : "−")\(ByteText.format(abs(item.logicalDelta)))").monospacedDigit() }
                        }
                    }
                    if let reason = comparison.reason { Text(L10n.message(reason)).font(.caption).foregroundStyle(.secondary) }
                    Text(L10n.text("Variação de arquivos não é uma promessa de espaço recuperável. As análises precisam ter o mesmo escopo e acesso.")).font(.caption).foregroundStyle(.secondary)
                }.padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.monitoringStatus.isEmpty { Text(L10n.message(model.monitoringStatus)).font(.caption).foregroundStyle(.secondary) }
            if model.history.isEmpty { ContentUnavailableView(L10n.text("Nenhuma operação realizada"), systemImage: "clock", description: Text(L10n.text("Analisar espaço não move nem apaga seus arquivos."))) }
            else {
                List(model.history) { record in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(L10n.message(record.title)).font(.headline); Spacer(); Text(record.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        Text(L10n.message(record.detail)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        if let delta = record.measuredFreeDelta { Text(L10n.text("Variação observada do espaço livre: \(delta >= 0 ? "+" : "−")\(ByteText.format(abs(delta)))")).font(.caption).foregroundStyle(Palette.accent) }
                        if let path = record.recoveryPath { Button(L10n.text("Mostrar local de recuperação")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.font(.caption) }
                    }.padding(.vertical, 10)
                }.listStyle(.inset)
            }
            Text(L10n.text("A variação de espaço livre inclui a atividade de outros aplicativos. Arquivos na Lixeira ainda ocupam espaço.")).font(.caption).foregroundStyle(.secondary)
        }.padding(30)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                PageHeader(title: L10n.text("Ajustes"), subtitle: L10n.text("Controle como o DiskWing acompanha suas ferramentas e armazena os próprios registros."))
                GroupBox(L10n.text("Idioma")) {
                    Picker(L10n.text("Idioma do aplicativo"), selection: Binding(get: { model.preferences.language }, set: { model.setLanguage($0) })) {
                        Text(L10n.text("Usar idioma do sistema")).tag("system")
                        Text(L10n.text("Português (Brasil)")).tag("pt-BR")
                        Text(L10n.text("English")).tag("en")
                    }.padding(10).accessibilityIdentifier("language-picker")
                }
                UpdateSettings(updates: model.updates).id(model.preferences.language)
                GroupBox(L10n.text("Acompanhamento opcional")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Selecione Acompanhar pasta no explorador para registrar mudanças. Nenhuma pasta é acompanhada por padrão."))
                        Toggle(L10n.text("Atualizar análises em segundo plano"), isOn: Binding(get: { model.preferences.backgroundRescans }, set: { model.preferences.backgroundRescans = $0; model.savePreferences() }))
                        Toggle(L10n.text("Alertar quando uma pasta crescer mais de 1 GiB"), isOn: Binding(get: { model.preferences.growthAlerts }, set: { model.setGrowthAlerts($0) }))
                        Text(L10n.text("As análises automáticas respeitam um intervalo mínimo de 15 minutos e pausam no modo de pouca energia. Os alertas são limitados a um por pasta por dia.")).font(.caption).foregroundStyle(.secondary)
                        ForEach(model.preferences.watchedFolders) { folder in
                            HStack { Text(folder.path).lineLimit(1).truncationMode(.middle); Spacer(); Button(L10n.text("Parar acompanhamento")) { model.removeWatch(folder.path) } }
                        }
                    }.padding(10)
                }
                GroupBox(L10n.text("Inicialização")) {
                    Toggle(L10n.text("Abrir DiskWing ao iniciar a sessão"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).padding(10)
                }
                GroupBox(L10n.text("Integração com o terminal")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Cada comando escolhe o cache disponível naquele momento. Preferências personalizadas têm prioridade. Programas já abertos mantêm seu ambiente até serem reabertos.")).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.text("Revisar integração…")) { model.review = .integration }
                            if model.settings.shellIntegrationEnabled { Button(L10n.text("Desativar integração…")) { model.review = .disableIntegration } }
                        }
                        Text(L10n.text("O executor também está no aplicativo: CacheSSDHelper run -- comando argumentos.")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(10)
                }
                GroupBox(L10n.text("Privacidade e permissões")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Nomes, tamanhos e histórico ficam neste Mac. Nenhuma análise é enviada a um servidor. Relatórios só são exportados quando você escolhe um destino."))
                        Text(L10n.text("Sem permissão para uma área, o resultado é marcado como parcial. Conceda Acesso Total ao Disco nos ajustes do macOS somente se precisar ampliar a análise.")).foregroundStyle(.secondary)
                        Button(L10n.text("Abrir Privacidade e Segurança")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                    }.padding(10)
                }
                GroupBox(L10n.text("Arquivos de compilação do Xcode")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Se o Xcode já aponta Derived Data para o SSD, é possível voltar ao local padrão do Mac. A cópia existente no SSD fica preservada. Encerre o Xcode antes de alterar.")).foregroundStyle(.secondary)
                        Button(L10n.text("Revisar retorno ao local padrão…")) { model.review = .xcodeLocal }.disabled(model.busy)
                    }.padding(10)
                }
                GroupBox(L10n.text("Registros e recuperação")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("São mantidas até 150 operações e 50 resumos de análise. O índice local mantém duas árvores por pasta analisada; o acompanhamento contínuo depende de sua escolha.")).foregroundStyle(.secondary)
                        Button(L10n.text("Mostrar registros locais")) { NSWorkspace.shared.open(model.store.base) }
                        Text(L10n.text("Prévia de desenvolvimento. Distribuição pública, notarização e validação com outras pessoas ainda não foram concluídas.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
            }.padding(30)
        }
    }
}

struct UpdateSettings: View {
    @ObservedObject var updates: Updates
    var body: some View {
        GroupBox(L10n.text("Atualizações")) {
            VStack(alignment: .leading, spacing: 12) {
                if updates.available {
                    Toggle(L10n.text("Verificar atualizações automaticamente"), isOn: Binding(get: { updates.enabled }, set: { updates.consent($0) }))
                    Button(L10n.text("Verificar agora…")) { updates.check() }.disabled(updates.sessionInProgress)
                    Text(L10n.text("As verificações acessam o servidor de atualizações após sua escolha. A instalação exige confirmação e atualizações assinadas. Nenhum inventário de arquivos é enviado.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("Esta compilação local não verifica atualizações. Atualizações assinadas serão habilitadas na distribuição pública.")).foregroundStyle(.secondary)
                }
            }.padding(10)
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
                fact(L10n.text("Ferramenta"), tool.name)
                fact(L10n.text("Origem"), tool.source.path)
                fact(L10n.text("Destino"), model.selectedVolume?.name ?? L10n.text("SSD não conectado"))
                fact(L10n.text("Tamanho encontrado"), ByteText.format(model.toolSizes[tool.id]?.logical ?? 0))
                Toggle(L10n.text("Liberar o cache local após copiar e validar"), isOn: Binding(get: { tool.canReleaseLocal && model.adapterStatuses[tool.id]?.canReleaseSource == true && model.releaseLocal }, set: { model.releaseLocal = $0 })).disabled(!tool.canReleaseLocal || model.adapterStatuses[tool.id]?.canReleaseSource != true)
                if tool.canReleaseLocal && model.adapterStatuses[tool.id]?.canReleaseSource != true { Text(L10n.text("A versão ou configuração desta ferramenta ainda não permite liberar a origem. Copie mantendo o cache local.")).font(.caption).foregroundStyle(Palette.orange) }
                if !tool.canReleaseLocal { Text(L10n.text("Nesta versão, a origem de \(tool.name) é mantida porque instalações existentes podem depender de links para esse cache. A cópia no SSD atende novas execuções compatíveis.")).font(.caption).foregroundStyle(Palette.orange) }
                Text(L10n.text("Feche a ferramenta antes de continuar. Sem SSD, os caches podem ser baixados novamente. Os executáveis locais do npx não são removidos.")).font(.caption).foregroundStyle(.secondary)
            case .trash(let item): fact(L10n.text("Item"), item.path); fact(L10n.text("Tamanho encontrado"), ByteText.format(item.logicalBytes)); Text(L10n.text("A Lixeira não será esvaziada pelo aplicativo.")).font(.caption).foregroundStyle(.secondary)
            case .move(let item, let destination): fact(L10n.text("Origem"), item.path); fact(L10n.text("Pasta de destino"), destination.path); Text(L10n.text("A cópia ficará no destino e a origem na Lixeira. Só esvazie a Lixeira depois de revisar a cópia. Se o destino for externo, o arquivo dependerá dele para ser acessado.")).font(.caption).foregroundStyle(.secondary)
            case .integration: fact(L10n.text("Arquivo atualizado"), L10n.text("Configuração do terminal zsh")); Text(L10n.text("Uma cópia da configuração atual ficará nos registros do DiskWing. Uma configuração antiga reconhecida de temporários em disco externo será substituída pelo padrão do macOS. Abra um novo terminal após ativar.")).font(.callout)
            case .disableIntegration: Text(L10n.text("Abra um novo terminal após desativar. Caches existentes e cópias no SSD serão preservados."))
            case .restore(let tool): fact(L10n.text("Ferramenta"), tool.name); Text(L10n.text("A restauração só ocorre se houver espaço no Mac e o cache local estiver vazio. A cópia no SSD será mantida."))
            case .eject(let volume): fact(L10n.text("Disco"), volume.name); Text(L10n.text("Novas execuções passam a usar o Mac. Se houver arquivos abertos, a ejeção será adiada. Outros aplicativos também podem impedir a ejeção pelo macOS."))
            case .recover(let assessment), .resolve(let assessment):
                fact(L10n.text("Origem registrada"), assessment.journal.source)
                Text(L10n.message(assessment.explanation))
                Text(L10n.text("Restaurar só usa uma cópia conferida e nunca sobrescreve a origem. Encerrar o registro mantém todas as cópias."))
            case .xcodeLocal: Text(L10n.text("Uma cópia das preferências de Derived Data ficará nos registros locais. O Xcode usará a pasta padrão do armazenamento interno. Nada será apagado no SSD."))
            }
            Divider()
            HStack { Button(L10n.text("Cancelar"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(action.title) { model.execute(action) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 560)
    }
    private func fact(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
    private var symbol: String { switch action { case .trash: return "trash"; case .eject: return "eject.circle"; case .integration, .disableIntegration: return "terminal"; default: return "externaldrive.badge.checkmark" } }
    private var description: String {
        switch action {
        case .migration: return L10n.text("Confira a origem e o destino. A migração copia o conteúdo, verifica sua integridade e valida a ferramenta antes de liberar a origem.")
        case .trash: return L10n.text("Este item será enviado à Lixeira do macOS. Revise seu conteúdo antes de confirmar.")
        case .move: return L10n.text("O aplicativo confere a cópia antes de enviar a origem à Lixeira. Nada existente no destino será sobrescrito.")
        case .integration: return L10n.text("Ative o direcionamento nas novas execuções do terminal. A ausência do SSD devolve os padrões locais.")
        case .disableIntegration: return L10n.text("Remova a integração dos novos terminais e volte a usar os caches locais.")
        case .restore: return L10n.text("Recupere uma cópia do cache para o armazenamento interno.")
        case .eject: return L10n.text("Prepare o retorno aos caches locais antes de desconectar o SSD.")
        case .recover: return L10n.text("Revise a cópia de recuperação antes de restaurar a origem.")
        case .resolve: return L10n.text("Encerre o aviso após revisar as cópias. Nenhum arquivo será removido.")
        case .xcodeLocal: return L10n.text("Restabeleça o destino local dos arquivos recriáveis de compilação do Xcode.")
        }
    }
}

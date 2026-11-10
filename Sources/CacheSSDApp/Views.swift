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
                List([AppSection.explorer, .caches, .history, .preferences]) { section in
                    Button { model.section = section } label: { HStack { Label(L10n.message(section.rawValue), systemImage: section.symbol); Spacer(minLength: 0) }.padding(.vertical, 7).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .listRowBackground(model.section == section ? Palette.accent.opacity(0.18) : Color.clear)
                        .accessibilityIdentifier("section-" + section.rawValue)
                        .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.text("Dados no seu Mac e SSD"), systemImage: "internaldrive")
                    Text(model.isProductionBuild ? L10n.text("Processamento local") : L10n.text("Processamento local · prévia de desenvolvimento")).font(.caption).foregroundStyle(.secondary)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let state = model.sampleState { SampleModeBanner(state: state) }
                    if model.pendingRecoveryCount > 0 {
                        HStack {
                            Label(L10n.text("Há \(model.pendingRecoveryCount) registros que precisam de revisão."), systemImage: "exclamationmark.circle")
                            Spacer()
                            Button(L10n.text("Revisar recuperação")) { model.section = .history }.accessibilityIdentifier("review-pending-recovery")
                        }.font(.callout).padding(12).background(Palette.orange.opacity(0.12)).accessibilityElement(children: .contain)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = model.operationMessage {
                    HStack(spacing: 12) { ProgressView().controlSize(.small); Text(L10n.message(message)); Spacer(); if let hint = model.operationHint { Text(hint).foregroundStyle(.secondary) }; Button(L10n.text("Cancelar operação")) { model.cancel() } }.font(.callout).padding(14).background(.bar)
                }
            }
            .toolbar {
                ToolbarItem { Button { model.chooseVolume() } label: { Label(L10n.text("Escolher volume"), systemImage: "externaldrive") }.disabled(model.busy || model.isScanning) }
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
                PageHeader(title: L10n.text("Mais espaço no Mac, caches no SSD."), subtitle: L10n.text("Direcione caches compatíveis para o SSD e explore o armazenamento para escolher o que enviar à Lixeira."))
                ForEach(model.volumes) { volume in DriveView(volume: volume) }
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Por onde começar")).font(.title3.weight(.semibold))
                    Button { model.scanInternalStorage() } label: {
                        Label(L10n.text("Analisar armazenamento interno"), systemImage: "internaldrive")
                    }.disabled(model.busy || model.isScanning).accessibilityIdentifier("scan-internal-storage")
                    Text(L10n.text("Analisa os arquivos acessíveis do volume de dados. O sistema protegido e outros volumes são escopos separados; áreas sem acesso aparecem como parciais.")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        QuickScan(title: L10n.text("Pasta pessoal"), detail: L10n.text("Uma visão dos seus arquivos"), symbol: "house", url: model.home)
                        QuickScan(title: L10n.text("Downloads"), detail: L10n.text("Instaladores e arquivos baixados"), symbol: "arrow.down.circle", url: model.home.appendingPathComponent("Downloads"))
                        QuickScan(title: L10n.text("Caches"), detail: L10n.text("Arquivos que podem ser recriados"), symbol: "shippingbox", url: model.home.appendingPathComponent("Library/Caches"))
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 33, weight: .light)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Preserve os caches compatíveis no SSD.")).font(.title3.weight(.semibold))
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
    var body: some View { VolumeExplorerContent() }
}

struct Metric: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 21, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8); Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
}

struct ItemMenu: View {
    @EnvironmentObject var model: AppModel
    let item: ScanItem
    var body: some View {
        Button(L10n.text("Mostrar no Finder")) { model.showInFinder(item) }
        if item.isDirectory { Button(L10n.text("Abrir pasta")) { model.openFolder(item) }.disabled(model.isScanning || model.busy) }
        Divider()
        Button(L10n.text("Revisar movimentação…")) { model.reviewMove(item) }.disabled(model.cachePolicyReason(item) != nil || model.busy || model.isScanning)
        Button(L10n.text("Revisar envio à Lixeira…")) { model.reviewTrash(item) }.disabled(model.trashPolicyReason(item) != nil || model.busy || model.isScanning)
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
                    Text(model.sizeText(item)).font(.system(size: 25, weight: .medium, design: .rounded))
                    Text(L10n.message(item.category.rawValue)).foregroundStyle(.secondary)
                    Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    if let reason = model.cachePolicyReason(item) { Text(L10n.text("Movimentação: \(L10n.message(reason))")).font(.callout).foregroundStyle(.secondary) }
                    else { Text(L10n.text("Revise o conteúdo antes de escolher uma ação. O tamanho não indica se um arquivo é dispensável.")).font(.callout).foregroundStyle(.secondary) }
                    Button(L10n.text("Mostrar no Finder")) { model.showInFinder(item) }.frame(maxWidth: .infinity, alignment: .leading)
                    if item.isDirectory {
                        Button(L10n.text("Abrir pasta")) { model.openFolder(item) }.disabled(model.isScanning || model.busy)
                        Button(L10n.text("Abrir pasta")) { model.openFolder(item) }.disabled(model.isScanning || model.busy)
                    }
                    if model.cachePolicyReason(item) == nil {
                        Button(L10n.text("Revisar movimentação…")) { model.reviewMove(item) }.disabled(model.busy || model.isScanning)
                    }
                    if let reason = model.trashPolicyReason(item) {
                        Text(L10n.message(reason)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        if let warning = model.trashWarning(item) { Text(warning).font(.caption).foregroundStyle(Palette.orange) }
                        Button(L10n.text("Revisar envio à Lixeira…")) { model.reviewTrash(item) }.disabled(model.busy || model.isScanning)
                    }
                    if item.category == .cache || item.category == .developer { Button(L10n.text("Ver integrações de cache")) { model.section = .caches } }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            } else { VStack(spacing: 12) { Image(systemName: "sidebar.right").font(.largeTitle).foregroundStyle(.tertiary); Text(L10n.text("Selecione um item para ver detalhes e ações.")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(28).frame(maxWidth: .infinity) }
        }.background(Palette.panel)
    }
}

struct CachesView: View {
    var body: some View { CacheWorkflowContent() }
}

struct CacheRow: View {
    @EnvironmentObject var model: AppModel
    let tool: CacheDescriptor
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "shippingbox").font(.title2.weight(.light)).foregroundStyle(Palette.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(tool.name).font(.headline); if let status = model.cacheStatus(tool) { Text(status).font(.caption).foregroundStyle(Palette.accent) } }
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
                Button(L10n.text("Revisar migração…")) { model.review = .migration(tool) }.disabled(model.selectedVolume == nil || model.destinationIssue != nil || (model.toolSizes[tool.id]?.logical ?? 0) == 0 || model.toolSizes[tool.id]?.complete != true || model.adapterStatuses[tool.id]?.state != "native-available")
                Button(L10n.text("Preparar novos caches no SSD…")) { model.review = .prepareCache(tool) }.disabled(model.selectedVolume == nil || model.destinationIssue != nil || model.settings.locations[tool.id] != nil || model.adapterStatuses[tool.id]?.state != "native-available" || !(model.toolSizes[tool.id].map { $0.missing || $0.complete && $0.logical == 0 } ?? false))
                Button(L10n.text("Mostrar cache local")) { model.reveal([tool.source]) }
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
            if model.hasUnreadableRecoveryRecords {
                Label(L10n.text("Há registros de recuperação ou configuração pendentes. Eles foram preservados; abra os registros locais para revisão."), systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
                Button(L10n.text("Mostrar registros locais")) { model.openRecords() }
            }
            ForEach(model.graphicalPendingTransfers) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("Transferência de cache precisa de revisão"), systemImage: "exclamationmark.circle").font(.headline)
                    Text(L10n.message(record.detail)).font(.caption)
                    Button(L10n.text("Revisar recuperação…")) { model.review = .graphicalRecover(record.id) }.disabled(model.busy)
                }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.recoveries.isEmpty {
                ForEach(model.recoveries) { assessment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.recoveryTitle(assessment)).font(.headline)
                        Text(L10n.message(assessment.explanation)).font(.callout)
                        Text(assessment.journal.source).font(.caption).textSelection(.enabled)
                        HStack {
                            if assessment.canRestoreSource { Button(assessment.journal.kind == "restore" ? L10n.text("Concluir restauração…") : L10n.text("Revisar recuperação…")) { model.review = .recover(assessment) } }
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
                            if let path = journal.localQuarantine, FileManager.default.fileExists(atPath: path) { Button(L10n.text("Mostrar origem preservada")) { model.reveal([URL(fileURLWithPath: path)]) }.font(.caption) }
                        }
                    }
                    Button(L10n.text("Abrir registros de recuperação")) { model.openRecords() }
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
                        if let path = record.recoveryPath { Button(L10n.text("Mostrar local de recuperação")) { model.reveal([URL(fileURLWithPath: path)]) }.font(.caption) }
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
                        Button(L10n.text("Abrir Privacidade e Segurança")) { model.openPrivacy() }
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
                        Button(L10n.text("Mostrar registros locais")) { model.openRecords() }
                        if model.isProductionBuild { Text(verbatim: model.applicationVersionDescription).font(.caption).foregroundStyle(.secondary) }
                        else { Text(L10n.text("Prévia de desenvolvimento. Distribuição pública, notarização e validação com outras pessoas ainda não foram concluídas.")).font(.caption).foregroundStyle(.secondary) }
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
        VStack(spacing: 0) {
          ScrollView {
           VStack(alignment: .leading, spacing: 20) {
            Label(action.title, systemImage: symbol).font(.title2.weight(.semibold))
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch action {
            case .graphicalRestore(let id), .graphicalResume(let id):
                fact(L10n.text("Cache"), model.cacheEntries.first(where: { $0.id == id })?.title ?? id)
                Text(L10n.text("Feche o aplicativo antes de continuar. Dados já existentes não serão sobrescritos; cópias e caches temporários serão preservados para recuperação.")).font(.callout).foregroundStyle(.secondary)
            case .graphicalRecover(let id):
                Text(L10n.text("A operação interrompida será revista usando suas identidades e cópias verificadas. Nenhum dado existente será substituído.")).font(.callout)
                if let record = model.graphicalPendingTransfers.first(where: { $0.id == id }) { fact(L10n.text("Origem"), record.sourceURL.path); Text(L10n.message(record.detail)).font(.caption) }
            case .cacheTransfer(let plan): CacheTransferReviewContent(plan: plan)
            case .migration(let tool):
                fact(L10n.text("Ferramenta"), tool.name)
                fact(L10n.text("Origem"), tool.source.path)
                fact(L10n.text("Destino"), model.selectedVolume?.name ?? L10n.text("SSD não conectado"))
                fact(L10n.text("Tamanho encontrado"), ByteText.format(model.toolSizes[tool.id]?.logical ?? 0))
                Toggle(L10n.text("Liberar o cache local após copiar e validar"), isOn: Binding(get: { tool.canReleaseLocal && model.adapterStatuses[tool.id]?.canReleaseSource == true && model.releaseLocal }, set: { model.releaseLocal = $0 })).disabled(!tool.canReleaseLocal || model.adapterStatuses[tool.id]?.canReleaseSource != true)
                if tool.canReleaseLocal && model.adapterStatuses[tool.id]?.canReleaseSource != true { Text(L10n.text("A versão ou configuração desta ferramenta ainda não permite liberar a origem. Copie mantendo o cache local.")).font(.caption).foregroundStyle(Palette.orange) }
                if !tool.canReleaseLocal { Text(L10n.text("Nesta versão, a origem de \(tool.name) é mantida porque instalações existentes podem depender de links para esse cache. A cópia no SSD atende novas execuções compatíveis.")).font(.caption).foregroundStyle(Palette.orange) }
                Text(L10n.text("Feche a ferramenta antes de continuar. Sem SSD, os caches podem ser baixados novamente. Os executáveis locais do npx não são removidos.")).font(.caption).foregroundStyle(.secondary)
            case .prepareCache(let tool):
                fact(L10n.text("Ferramenta"), tool.name)
                fact(L10n.text("Destino"), model.selectedVolume?.name ?? L10n.text("SSD não conectado"))
                Text(L10n.text("Prepara uma pasta vazia no SSD para novas gravações. Nenhum cache local será criado ou removido. O direcionamento exige a integração atualizada em um novo terminal.")).font(.callout)
            case .volumeTrash(let item, let scope):
                fact(L10n.text("Volume"), model.context.operationVolumeProvider()(scope.volumeUUID)?.name ?? L10n.text("Volume indisponível"))
                fact(L10n.text("Item"), (try? scope.resolve(volumeProvider: model.context.operationVolumeProvider()))?.path ?? scope.reviewedPath)
                fact(L10n.text("Tamanho encontrado"), model.sizeText(item))
                if let warning = model.trashWarning(item) { Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Palette.orange) }
                Text(L10n.text("Links, conteúdo da nuvem não baixado e dados protegidos não serão excluídos por este fluxo.")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("A Lixeira não será esvaziada pelo aplicativo. O espaço continua ocupado até você esvaziá-la no Finder.")).font(.caption).foregroundStyle(.secondary)
            case .trash(let item):
                fact(L10n.text("Item"), item.path); fact(L10n.text("Tamanho encontrado"), model.sizeText(item))
                if let warning = model.trashWarning(item) { Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Palette.orange) }
                Text(L10n.text("Links, conteúdo da nuvem não baixado e dados protegidos não serão excluídos por este fluxo.")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("A Lixeira não será esvaziada pelo aplicativo. O espaço continua ocupado até você esvaziá-la no Finder.")).font(.caption).foregroundStyle(.secondary)
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
           }.padding(28)
          }
            Divider()
            HStack { Button(L10n.text("Cancelar"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(action.title) { model.execute(action) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: 560).frame(minHeight: 320, idealHeight: 500, maxHeight: 620)
    }
    private func fact(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
    private var symbol: String { switch action { case .volumeTrash, .trash: return "trash"; case .eject: return "eject.circle"; case .integration, .disableIntegration: return "terminal"; default: return "externaldrive.badge.checkmark" } }
    private var description: String {
        switch action {
        case .graphicalRestore: return L10n.text("Retorne o cache ao Mac usando uma cópia verificada, sem sobrescrever dados locais.")
        case .graphicalResume: return L10n.text("Revise o retorno ao SSD e preserve os dados temporários sem misturar gerações.")
        case .graphicalRecover: return L10n.text("Revise a recuperação deste cache antes de continuar.")
        case .cacheTransfer: return L10n.text("Revise os aplicativos e o SSD. O resultado será acompanhado por aplicativo, sem esconder exceções.")
        case .migration: return L10n.text("Confira a origem e o destino. A migração copia o conteúdo, verifica sua integridade e valida a ferramenta antes de liberar a origem.")
        case .prepareCache: return L10n.text("Escolha onde serão gravados os próximos caches desta ferramenta.")
        case .volumeTrash, .trash: return L10n.text("Este item será enviado à Lixeira do macOS. Revise seu conteúdo antes de confirmar.")
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


struct SampleModeBanner: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var state: SampleState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("Modo de amostras — seus dados reais não são usados"), systemImage: "testtube.2").font(.headline)
            Text(L10n.text("Arquivos, SSD e integrações do sistema são isolados ou simulados. A sessão é preservada para testar reinício e recuperação.")).font(.caption)
            HStack {
                Button(L10n.text("Analisar amostras")) { model.chooseFolder() }.disabled(model.busy || model.isScanning).accessibilityIdentifier("sample-scan")
                Toggle(L10n.text("SSD de amostra conectado"), isOn: Binding(get: { state.volumeConnected }, set: { model.setSampleVolumeConnected($0) })).toggleStyle(.checkbox).accessibilityIdentifier("sample-volume-connected")
                Toggle(L10n.text("Simular pouca energia"), isOn: $state.lowPower).toggleStyle(.checkbox).accessibilityIdentifier("sample-low-power")
                if model.isSamples {
                    Menu {
                        Button(L10n.text("Janela mínima")) { (NSApp.keyWindow ?? NSApp.mainWindow)?.setContentSize(NSSize(width: 1050, height: 690)) }.accessibilityIdentifier("sample-window-minimum")
                        Button(L10n.text("Tamanho padrão")) { (NSApp.keyWindow ?? NSApp.mainWindow)?.setContentSize(NSSize(width: 1240, height: 810)) }.accessibilityIdentifier("sample-window-default")
                    } label: {
                        Label(L10n.text("Tamanho da janela"), systemImage: "macwindow").labelStyle(.iconOnly)
                    }.help(L10n.text("Tamanho da janela")).accessibilityLabel(L10n.text("Tamanho da janela")).accessibilityIdentifier("sample-window-size")
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.1)).accessibilityIdentifier("sample-mode-banner")
    }
}

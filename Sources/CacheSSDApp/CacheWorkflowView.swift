import SwiftUI
import AppKit
import CacheSSDCore

struct CacheWorkflowContent: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: L10n.text("Caches no SSD"), subtitle: L10n.text("Transfira os caches compatíveis e acompanhe onde seus aplicativos estão gravando."))
                HStack(spacing: 16) {
                    Image(systemName: "externaldrive").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("SSD para os caches")).font(.headline)
                        Text(L10n.text("Sem ele, os aplicativos continuam funcionando. Exceções ficam visíveis.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(L10n.text("SSD para os caches"), selection: Binding(get: { model.settings.selectedVolumeUUID ?? "" }, set: { model.settings.selectedVolumeUUID = $0.isEmpty ? nil : $0; model.saveSettings(); model.invalidateCacheReview() })) {
                        Text(L10n.text("Escolher SSD…")).tag("")
                        ForEach(model.volumes.filter { !$0.isInternal }) { volume in Text(volume.name + " · " + ByteText.format(volume.freeBytes)).tag(volume.uuid) }
                        if let id = model.settings.selectedVolumeUUID, !model.volumes.contains(where: { $0.uuid == id }) { Text(L10n.text("SSD desconectado")).tag(id) }
                    }.labelsHidden().frame(maxWidth: 300).disabled(model.busy || model.isScanning || model.cacheAnalyzing)
                }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                if let issue = model.destinationIssue { Label(issue, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Palette.orange) }
                VStack(alignment: .leading, spacing: 9) {
                    Label(model.cacheWorkflowHeadline, systemImage: model.cacheTransferResults.contains { $0.state == .ssdVerified } ? "externaldrive.badge.checkmark" : "shippingbox").font(.title3.weight(.semibold))
                    Text(model.cacheWorkflowDetail).font(.callout).foregroundStyle(.secondary)
                    if model.canVerifyGraphicalCacheUsage {
                        Button(L10n.text("Verificar uso e concluir transferência")) { model.verifyCacheWorkflowUsage() }.disabled(model.busy || model.isScanning || model.cacheAnalyzing)
                        Text(L10n.text("Durante a verificação, reabra o Chrome ou carregue uma página. Se ele estiver parado, o resultado pode continuar aguardando uso.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if model.cacheAnalyzing { ProgressView().controlSize(.small); Text(L10n.text("Identificando aplicativos e medindo caches…")).font(.callout) }
                    else { Button(model.cacheEntries.isEmpty ? L10n.text("Analisar caches") : L10n.text("Analisar novamente")) { model.analyzeCacheWorkflow() }.disabled(model.busy || model.isScanning) }
                    Spacer()
                    if !model.cacheEntries.isEmpty {
                        Button(L10n.text("Revisar transferência…")) { model.reviewCacheTransfer() }.buttonStyle(.borderedProminent)
                            .disabled(model.busy || model.isScanning || model.cacheAnalyzing || model.newCacheTransferBlocked || model.selectedCacheTransferEntries.isEmpty || model.selectedVolume == nil || model.destinationIssue != nil)
                    }
                }
                if !model.cacheEntries.isEmpty {
                    let eligible = model.cacheEntries.filter { $0.blockedReason == nil && !model.cacheRegisteredIDs.contains($0.id) }
                    let configured = model.cacheEntries.filter { model.cacheRegisteredIDs.contains($0.id) }
                    let exceptions = model.cacheEntries.filter { $0.blockedReason != nil && !model.cacheRegisteredIDs.contains($0.id) }
                    if !configured.isEmpty {
                        Text(L10n.text("Acompanhar destinos")).font(.headline)
                        ForEach(configured) { entry in CacheWorkflowRow(entry: entry, selectable: false) }
                    }
                    if !eligible.isEmpty {
                        HStack {
                            Text(L10n.text("Prontos para o SSD")).font(.headline)
                            Spacer()
                            Text(L10n.text("\(ByteText.format(eligible.reduce(0) { $0 + $1.logicalBytes })) de dados encontrados")).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(eligible) { entry in CacheWorkflowRow(entry: entry, selectable: true) }
                    }
                    if !exceptions.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.text("Continuam no Mac")).font(.headline)
                            Text(L10n.text("\(ByteText.format(exceptions.filter { model.cacheSizeKnown($0) }.reduce(0) { $0 + $1.logicalBytes })) conhecidos. Estes itens não contam como transferidos.")).font(.caption).foregroundStyle(.secondary)
                        }
                        if exceptions.contains(where: { !model.cacheSizeKnown($0) }) {
                            Text(L10n.text("\(exceptions.filter { !model.cacheSizeKnown($0) }.count) itens com tamanho desconhecido, preservados no Mac.")).font(.caption).foregroundStyle(.secondary)
                        }
                        CacheExceptionsList(entries: exceptions)
                    }
                } else if !model.cacheAnalyzing {
                    Text(L10n.text("O SSD escolhido e a integração, sozinhos, não transferem nenhum cache. A análise mostra o que pode sair do Mac com segurança.")).font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup(L10n.text("Detalhes e recuperação")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Perfis, contas, senhas, projetos e instalações ficam preservados. Não há limpeza automática. O espaço realmente disponível pode diferir dos tamanhos somados.")).font(.caption)
                        Text(model.integrationIsCurrent ? L10n.text("Integração preparada para novos terminais") : L10n.text("A integração necessária será revisada junto com a transferência.")).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("Abrir histórico e recuperação")) { model.section = .history }
                        if let volume = model.selectedVolume { Button(L10n.text("Preparar para ejetar \(volume.name)…")) { model.review = .eject(volume) }.disabled(model.busy || model.isScanning) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.padding(28)
        }
    }
}

private struct CacheExceptionsList: View {
    @EnvironmentObject var model: AppModel
    let entries: [CacheTransferEntry]
    private struct Group: Identifiable { let id: String; let title: String; let entries: [CacheTransferEntry] }
    private var groups: [Group] {
        let grouped = Dictionary(grouping: entries) { entry in
            model.graphicalCacheCandidates.first { $0.id == entry.id }?.applicationID ?? entry.id
        }
        return grouped.map { id, entries in
            Group(id: id, title: id == GraphicalCacheCatalog.chromeBundleID ? "Google Chrome" : entries[0].title, entries: entries)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        ForEach(groups) { group in
            if group.entries.count == 1, let entry = group.entries.first { CacheWorkflowRow(entry: entry, selectable: false) }
            else {
                DisclosureGroup {
                    ForEach(group.entries) { entry in CacheWorkflowRow(entry: entry, selectable: false) }
                } label: {
                    HStack {
                        Text(group.title).font(.headline)
                        Spacer()
                        Text(L10n.text("\(group.entries.count) caches locais · \(ByteText.format(group.entries.filter { model.cacheSizeKnown($0) }.reduce(0) { $0 + $1.logicalBytes })) conhecidos")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(14).background(Palette.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct CacheWorkflowRow: View {
    @EnvironmentObject var model: AppModel
    let entry: CacheTransferEntry
    let selectable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                if selectable {
                    Toggle("", isOn: Binding(get: { model.cacheSelectedIDs.contains(entry.id) }, set: { if $0 { model.cacheSelectedIDs.insert(entry.id) } else { model.cacheSelectedIDs.remove(entry.id) } })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel(L10n.text("Selecionar \(entry.title)"))
                }
                if let url = model.graphicalCacheCandidates.first(where: { $0.id == entry.id })?.applicationURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                } else { Image(systemName: entry.kind == .graphical ? "app" : "terminal").font(.title2).foregroundStyle(Palette.accent).frame(width: 28) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.headline)
                    Text(L10n.message(entry.scopeLabel)).font(.caption).foregroundStyle(.secondary)
                    if let result = model.cacheTransferResults.first(where: { $0.id == entry.id }) {
                        Text(model.cacheStateText(result.state)).font(.callout.weight(.medium)).foregroundStyle(result.state == .error || result.state == .exception ? Palette.orange : Palette.accent)
                        Text(L10n.message(result.detail)).font(.caption).foregroundStyle(.secondary)
                        if let date = model.cacheVerifiedAt[entry.id] { Text(L10n.text("Último uso comprovado: \(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(L10n.locale)))")).font(.caption).foregroundStyle(.secondary) }
                    } else if let reason = entry.blockedReason { Text(L10n.message(reason)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Text(model.cacheSizeKnown(entry) ? ByteText.format(entry.logicalBytes) : L10n.text("Desconhecido")).font(.callout).monospacedDigit()
            }
            if entry.kind == .commandLine, model.cacheRegisteredIDs.contains(entry.id), let tool = model.tools.first(where: { $0.id == entry.id }) {
                Button(L10n.text("Restaurar no Mac…")) { model.review = .restore(tool) }.font(.caption)
            }
            if entry.kind == .graphical, model.cacheRegisteredIDs.contains(entry.id) {
                HStack {
                    Button(L10n.text("Restaurar no Mac…")) { model.review = .graphicalRestore(entry.id) }
                    if model.cacheTransferResults.first(where: { $0.id == entry.id })?.state == .localTemporary { Button(L10n.text("Retomar no SSD…")) { model.review = .graphicalResume(entry.id) } }
                }.font(.caption)
            }
            DisclosureGroup(L10n.text("Ver detalhes")) {
                VStack(alignment: .leading, spacing: 5) {
                    if let version = model.graphicalCacheCandidates.first(where: { $0.id == entry.id })?.applicationVersion { Text(L10n.text("Versão: \(version)")) }
                    Text(entry.sourceURL.path).textSelection(.enabled)
                    if let destination = model.cacheDestination(entry) { Text(destination.path).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).padding(.leading, selectable ? 30 : 0)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel.opacity(selectable ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 7))
        .disabled(model.busy || model.isScanning)
    }
}

struct CacheTransferReviewContent: View {
    @EnvironmentObject var model: AppModel
    let plan: CacheTransferPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("SSD escolhido: \(plan.destinationVolume.name)")).font(.headline)
            Text(L10n.text("\(plan.eligibleEntries.count) itens selecionados · \(ByteText.format(plan.eligibleLogicalBytes)) de dados")).font(.callout)
            Text(L10n.text("Feche os aplicativos e ferramentas indicados antes de continuar. Nenhum processo será encerrado à força. A transferência copia, confere, ativa o destino e só libera a origem quando isso foi qualificado.")).font(.callout).foregroundStyle(.secondary)
            if plan.eligibleEntries.contains(where: { $0.kind == .graphical }) {
                Button(L10n.text("Solicitar encerramento dos aplicativos")) { model.closeReviewedApplications(plan) }
                Text(L10n.text("Confirme o salvamento de trabalho nos próprios aplicativos. Se algum continuar aberto, a transferência será recusada.")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(plan.eligibleEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.headline)
                    Text(L10n.message(entry.scopeLabel)).font(.caption).foregroundStyle(.secondary)
                    if entry.isSourceMissing { Text(L10n.text("Prepara o destino para os próximos caches.")).font(.caption) }
                    else if entry.canReleaseSource { Text(entry.kind == .graphical ? L10n.text("Origem preservada até comprovar uso do SSD pelo aplicativo.") : L10n.text("Origem local liberada após conferência e ativação.")).font(.caption) }
                    if entry.kind == .commandLine { Text(L10n.text("Requer um novo terminal para as próximas execuções.")).font(.caption).foregroundStyle(Palette.orange) }
                }
            }
            if plan.eligibleEntries.contains(where: { $0.kind == .commandLine }), !model.integrationIsCurrent {
                Text(L10n.text("A configuração do terminal será atualizada com cópia de segurança. Abra um novo terminal depois de concluir.")).font(.callout).foregroundStyle(Palette.orange)
            }
            Text(L10n.text("Sem SSD, os aplicativos qualificados continuam funcionando com cache temporário. Uma desconexão durante uma operação pode interrompê-la.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

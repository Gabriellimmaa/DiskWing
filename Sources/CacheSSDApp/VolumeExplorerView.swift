import SwiftUI
import CacheSSDCore

struct VolumeExplorerContent: View {
    @EnvironmentObject var model: AppModel
    @State private var inspector = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.explorerTarget.map { model.volumeTitle($0) } ?? L10n.text("Explorar volumes")).font(.system(size: 27, weight: .semibold))
                    Text(model.choosingVolume || model.report == nil ? L10n.text("Escolha um volume para encontrar o que ocupa espaço.") : L10n.text("Árvore e mapa mostram o mesmo volume. Selecione um item para revisar suas opções.")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.chooseVolume() } label: { Label(L10n.text("Escolher volume"), systemImage: "internaldrive") }.disabled(model.busy || model.isScanning)
                if model.report != nil && !model.choosingVolume {
                    Button { model.refreshExplorer() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy || model.isScanning).accessibilityLabel(L10n.text("Atualizar análise"))
                    Button { inspector.toggle() } label: { Image(systemName: "sidebar.right") }.accessibilityLabel(L10n.text("Detalhes do item"))
                }
            }.padding(24)
            if model.choosingVolume || model.report == nil && !model.isScanning {
                VolumeChooser()
            } else {
                if model.isScanning {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("Analisando o volume…")).font(.headline)
                            Text(L10n.text("\(model.scanProgress?.entries ?? 0) itens encontrados")).font(.caption)
                            Text(model.scanProgress?.currentPath ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(); Button(L10n.text("Interromper")) { model.cancel() }
                    }.padding(14).background(Palette.accent.opacity(0.07)).padding(.horizontal, 24)
                }
                if let report = model.report {
                    HStack(spacing: 24) {
                        Metric(label: L10n.text("Espaço alocado estimado"), value: model.sizeText(report.root, allocated: true))
                        Metric(label: L10n.text("Tamanho lógico"), value: model.sizeText(report.root))
                        Metric(label: L10n.text("Arquivos lidos"), value: report.root.fileCount.formatted(.number.locale(L10n.locale)))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Label(model.isScanning ? L10n.text("Analisando o volume…") : !model.currentScopeAvailable ? L10n.text("Volume ou índice indisponível") : model.analysisNeedsRefresh ? L10n.text("Análise desatualizada") : report.isPartial ? L10n.text("Análise parcial") : L10n.text("Análise concluída"), systemImage: report.isPartial || model.analysisNeedsRefresh || !model.currentScopeAvailable ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.caption).foregroundStyle(report.isPartial || model.analysisNeedsRefresh || !model.currentScopeAvailable ? Palette.orange : Palette.accent)
                            if report.isPartial && model.explorerTarget != nil { Button(L10n.text("Continuar análise")) { model.resumeExplorer() }.disabled(model.busy || model.isScanning) }
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 18)
                    Divider()
                    HStack(spacing: 10) {
                        Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(model.breadcrumbs.count <= 1).accessibilityLabel(L10n.text("Voltar à pasta anterior"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { position, folder in
                                    if position > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                                    Button(position == 0 ? model.explorerTarget.map { model.volumeTitle($0) } ?? model.explorerName(folder) : model.explorerName(folder)) { model.navigateToBreadcrumb(position) }.buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer()
                        Picker(L10n.text("Medida"), selection: $model.allocatedOrder) {
                            Text(L10n.text("Espaço em disco")).tag(true); Text(L10n.text("Tamanho lógico")).tag(false)
                        }.frame(width: 205)
                        Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(L10n.text("Exportar relatório"))
                            .disabled(model.busy || model.isScanning)
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                    if model.isScanning { Spacer() }
                    else if model.indexSuspended || !model.currentScopeAvailable {
                        ContentUnavailableView {
                            Label(model.indexSuspended ? L10n.text("Análise guardada no SSD") : L10n.text("Volume analisado indisponível"), systemImage: "externaldrive")
                        } description: {
                            Text(model.indexSuspended ? L10n.text("Reconecte o SSD e retome a análise. O índice e a fila foram preservados; ausência não é tamanho zero.") : L10n.text("O volume ou sua identidade mudou. Reconecte o volume original e retome, ou escolha um volume novamente. Os totais anteriores foram preservados."))
                        } actions: {
                            Button(L10n.text("Retomar análise")) { model.resumeExplorer() }.disabled(model.busy || model.isScanning)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                    HSplitView {
                        VStack(spacing: 0) {
                            TextField(L10n.text("Buscar em todo o volume"), text: $model.search).textFieldStyle(.roundedBorder).padding(12).accessibilityIdentifier("explorer-search")
                            VolumeTreeView(model: model).frame(minWidth: 360)
                        }
                        VolumeTreemapView().frame(minWidth: 220, idealWidth: 320)
                        if inspector { InspectorView(item: model.selectedItem).frame(minWidth: 210, idealWidth: 230, maxWidth: 280) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let item = model.selectedItem {
                        HStack {
                            Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(L10n.text("Mostrar no Finder")) { model.showInFinder(item) }
                            Button(L10n.text("Revisar envio à Lixeira…")) { model.reviewTrash(item) }.disabled(model.trashPolicyReason(item) != nil || model.busy || model.isScanning)
                        }.padding(.horizontal, 16).padding(.vertical, 9).background(.bar)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Blocos podem ser compartilhados. O mapa não representa uma promessa de espaço recuperável. Links e outros volumes não são percorridos."))
                        if report.isPartial { Text(L10n.text("Há áreas sem acesso, ainda não lidas ou interrompidas. Os totais são parciais.")).foregroundStyle(Palette.orange) }
                        Text(model.indexOnSSD ? L10n.text("Índice desta análise guardado no SSD.") : L10n.text("Índice desta análise guardado no Mac, com limite de espaço."))
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                } else { Spacer() }
            }
        }
    }
}

private struct VolumeChooser: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(model.volumeTargets) { target in
                    Button { model.scanVolume(target) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: target.roots.contains { $0.isInternal } ? "internaldrive" : "externaldrive").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.volumeTitle(target)).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text(target.isSystemGroup ? L10n.text("Sistema e dados do Mac em uma árvore, sem duplicar pastas.") : L10n.text("Analisar tudo que estiver acessível neste volume.")).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let root = target.roots.first {
                                Text(L10n.text("\(ByteText.format(Volumes.free(at: root.url))) livres")).font(.callout).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(model.busy || model.isScanning).accessibilityIdentifier("scan-volume-" + target.id)
                    if model.resumableVolumeIDs.contains(target.id) {
                        HStack { Spacer(); Button(L10n.text("Retomar análise pendente")) { model.scanVolume(target, resume: true) }.disabled(model.busy || model.isScanning) }
                    }
                }
                if model.volumeTargets.isEmpty { ProgressView(L10n.text("Identificando volumes…")).padding(30) }
                Toggle(L10n.text("Guardar os dados da análise no SSD dos caches, quando disponível"), isOn: $model.preferExternalIndex).disabled(model.busy || model.isScanning)
                Text(L10n.text("Essa escolha afeta a lista da análise. O volume explorado e os caches dos aplicativos continuam separados. No Mac, a lista tem limite de espaço.")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("A análise lê nomes e tamanhos. Nenhum arquivo é alterado. O SSD dos caches é escolhido separadamente em Caches no SSD.")).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }.padding(24)
        }
    }
}

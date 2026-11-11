import SwiftUI
import CacheSSDCore

struct VolumeTreemapView: View {
    @EnvironmentObject var model: AppModel
    private let otherID = "diskwing-other-aggregate"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Mapa do espaço")).font(.headline)
                Spacer()
                Text(model.allocatedOrder ? L10n.text("Alocado estimado") : L10n.text("Tamanho lógico")).font(.caption).foregroundStyle(.secondary)
            }
            if !model.search.isEmpty || model.showLargest {
                ContentUnavailableView { Label(L10n.text("Busca em todo o volume"), systemImage: "magnifyingglass") } description: { Text(L10n.text("Abra uma pasta do resultado para ver seu mapa.")) }
            } else {
                GeometryReader { geometry in
                    let values = model.treemapItems.map { TreemapValue(id: $0.path, bytes: model.allocatedOrder ? $0.allocatedBytes : $0.logicalBytes) } + [TreemapValue(id: otherID, bytes: model.treemapOtherBytes)]
                    let tiles = TreemapLayout.tiles(values, width: geometry.size.width, height: geometry.size.height)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                        ForEach(tiles) { tile in
                            if tile.id == otherID {
                                tileView(tile, name: L10n.text("Outros \(model.treemapOtherCount) itens"), bytes: model.treemapOtherBytes, folder: true, selected: model.selectedInTreemapRemainder) {
                                    model.treeScrollRequest = (UUID(), model.treemapItems.count)
                                }
                            } else if let ordinal = model.treemapItems.firstIndex(where: { $0.path == tile.id }) {
                                let item = model.treemapItems[ordinal]
                                tileView(tile, name: model.explorerName(item) + (model.isKnownTrashed(item) ? " · " + L10n.text("Na Lixeira") : ""), bytes: model.allocatedOrder ? item.allocatedBytes : item.logicalBytes, folder: item.isDirectory, selected: model.treemapContainsSelection(item)) {
                                    model.selectExplorerItem(item, ordinal: ordinal)
                                }
                                .onTapGesture(count: 2) { if item.isDirectory { model.openFolder(item) } }
                                .contextMenu { ItemMenu(item: item) }
                            }
                        }
                        if tiles.isEmpty { Text(L10n.text("Sem tamanhos conhecidos para desenhar.")).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                }
                .accessibilityIdentifier("volume-treemap")
            }
            if let container = model.selectedTreemapContainer, let selected = model.selectedPath, selected != container.path {
                Text(L10n.text("Seleção dentro de \(model.explorerName(container)). Abra a pasta para detalhar o mapa.")).font(.caption).foregroundStyle(Palette.accent)
            } else if model.selectedInTreemapRemainder {
                Text(L10n.text("Seleção dentro de Outros. Use a árvore para abrir a pasta e detalhar o mapa.")).font(.caption).foregroundStyle(Palette.accent)
            }
            Text(L10n.text("Selecione um bloco para localizar na árvore. Abra uma pasta para aprofundar. Áreas desconhecidas não representam tamanho zero.")).font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func tileView(_ tile: TreemapTile, name: String, bytes: Int64, folder: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(folder ? Palette.accent.opacity(0.2) : Palette.secondary.opacity(0.12))
                Rectangle().strokeBorder(selected ? Palette.accent : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: selected ? 2 : 0.5)
                if tile.width > 50 && tile.height > 30 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 11, weight: .medium)).lineLimit(tile.height > 70 ? 2 : 1)
                        if tile.height > 46 { Text(ByteText.format(bytes)).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.padding(7)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).frame(width: max(0,tile.width-2), height: max(0,tile.height-2)).offset(x: tile.x+1, y: tile.y+1)
        .help(name + " · " + ByteText.format(bytes))
        .accessibilityLabel(name + ", " + ByteText.format(bytes))
    }
}

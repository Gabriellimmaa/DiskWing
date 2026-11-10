import AppKit
import SwiftUI
import CacheSSDCore

/// A table draws a virtual outline. Only expanded branch counts and a bounded
/// set of SQL pages live in memory; no NSObject per file is retained.
struct VolumeTreeView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = TreeScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let table = KeyTable(); table.headerView = NSTableHeaderView(); table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true; table.allowsMultipleSelection = false
        table.setAccessibilityIdentifier("volume-tree"); table.setAccessibilityLabel(L10n.text("Árvore do volume"))
        for (id, title, width) in [("name", L10n.text("Nome"), 320.0), ("size", L10n.text("Espaço em disco"), 120.0), ("share", "%", 60.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.minWidth = id == "name" ? 170 : 60; table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openSelection)
        table.keyHandler = { [weak coordinator = context.coordinator] event in coordinator?.key(event) ?? false }
        table.menu = NSMenu(); table.menu?.delegate = context.coordinator
        context.coordinator.table = table; scroll.documentView = table
        context.coordinator.update(model)
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.update(model) }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.invalidate() }

    final class TreeScrollView: NSScrollView {
        override func tile() {
            super.tile()
            guard let table = documentView as? NSTableView, table.tableColumns.count == 3 else { return }
            let width = max(340, contentSize.width)
            if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
            let widths = [max(170, width - 170), 110.0, 60.0]
            for (column, value) in zip(table.tableColumns, widths) where abs(column.width - value) > 0.5 { column.width = value }
        }
    }
    final class KeyTable: NSTableView {
        var keyHandler: ((NSEvent) -> Bool)?
        override func keyDown(with event: NSEvent) { if keyHandler?(event) != true { super.keyDown(with: event) } }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct PageKey: Hashable { let parent: String; let offset: Int }
        weak var table: NSTableView?
        var model: AppModel
        var branch = VirtualTreeBranch(path: "", childCount: 0)
        var pages: [PageKey: [ScanItem]] = [:], order: [PageKey] = [], pending: [PageKey: UUID] = [:]
        var signature = "", generation = UUID(), language = ""
        var activeReads = 0, rootLoaded = false
        var deferredExpansion: (parent: String, ordinal: Int, child: String)?
        var lastScrollRequest: UUID?
        var selectedReference: VirtualTreeReference?
        private var synchronizingSelection = false, active = true
        let pageSize = 128, pageBudget = 12
        init(model: AppModel) { self.model = model }
        func update(_ model: AppModel) {
            self.model = model
            let currentLanguage = L10n.isEnglish ? "en" : "pt-BR"
            if language != currentLanguage {
                language = currentLanguage
                table?.setAccessibilityLabel(L10n.text("Árvore do volume"))
                table?.tableColumns.first(where: { $0.identifier.rawValue == "name" })?.title = L10n.text("Nome")
                table?.tableColumns.first(where: { $0.identifier.rawValue == "size" })?.title = model.allocatedOrder ? L10n.text("Espaço em disco") : L10n.text("Tamanho lógico")
                reloadWithoutSelectionNotification()
            }
            let next = [model.explorerRevision.uuidString, model.indexedSessionID?.uuidString ?? "", model.currentFolder?.path ?? "", model.search, String(model.allocatedOrder), String(model.showLargest), model.minimumMiB].joined(separator: "\u{1f}")
            table?.tableColumns.first(where: { $0.identifier.rawValue == "size" })?.title = model.allocatedOrder ? L10n.text("Espaço em disco") : L10n.text("Tamanho lógico")
            if signature != next {
                signature = next; generation = UUID(); pages.removeAll(); order.removeAll(); pending.removeAll(); rootLoaded = false; deferredExpansion = nil
                branch = VirtualTreeBranch(path: model.currentFolder?.path ?? "", childCount: 0)
                selectedReference = nil
                reloadWithoutSelectionNotification(); request(parent: branch.path, offset: 0, root: true)
            }
            if let request = model.treeScrollRequest, lastScrollRequest != request.id,
               let row = branch.rowIndex(parent: branch.path, ordinal: request.ordinal) {
                lastScrollRequest = request.id
                table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table?.scrollRowToVisible(row)
            }
        }
        func invalidate() {
            active = false; generation = UUID(); pending.removeAll(); deferredExpansion = nil; rootLoaded = true; table = nil
        }
        func numberOfRows(in tableView: NSTableView) -> Int { branch.rowCount }
        func item(at row: Int) -> (ScanItem, VirtualTreeReference)? {
            guard let ref = branch.reference(at: row) else { return nil }
            let offset = ref.ordinal / pageSize * pageSize, key = PageKey(parent: ref.parent, offset: offset)
            guard let page = pages[key], ref.ordinal-offset < page.count else {
                request(parent: ref.parent, offset: offset); return nil
            }
            return (page[ref.ordinal-offset], ref)
        }
        func request(parent: String, offset: Int, root: Bool = false, expand: (String, Int)? = nil) {
            let key = PageKey(parent: parent, offset: offset)
            guard active, !parent.isEmpty, pending[key] != generation, model.indexedSessionID != nil else { return }
            guard activeReads < 3 else {
                if let expand { deferredExpansion = (expand.0, expand.1, parent) }
                return
            }
            let token = generation; pending[key] = token; activeReads += 1
            Task {
                defer {
                    activeReads -= 1
                    if pending[key] == token { pending.removeValue(forKey: key) }
                    if active {
                        if !rootLoaded { request(parent: branch.path, offset: 0, root: true) }
                        else if let deferred = deferredExpansion {
                            deferredExpansion = nil
                            request(parent: deferred.child, offset: 0, expand: (deferred.parent, deferred.ordinal))
                        } else { table?.reloadData() }
                    }
                }
                do {
                    let page = try await model.treePage(parent: parent, offset: offset, limit: pageSize)
                    guard generation == token else { return }
                    pages[key] = page.items; order.removeAll { $0 == key }; order.append(key)
                    while order.count > pageBudget { pages.removeValue(forKey: order.removeFirst()) }
                    if root { branch.childCount = page.total; rootLoaded = true }
                    if let (parentPath, ordinal) = expand { branch.setExpansion(parent: parentPath, ordinal: ordinal, branch: VirtualTreeBranch(path: parent, childCount: page.total)) }
                    reloadPreservingSelection()
                } catch {
                    guard generation == token else { return }; rootLoaded = true; model.errorMessage = error.localizedDescription
                }
            }
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let column = tableColumn?.identifier.rawValue ?? "name"
            guard let (item, ref) = item(at: row) else {
                return label(column == "name" ? L10n.text("Carregando…") : "", identifier: column)
            }
            if column == "name" {
                let cell = TreeNameCell(); cell.leading.constant = CGFloat(min(ref.depth, 8) * 12 + 4)
                let expanded = branch.isExpanded(parent: ref.parent, ordinal: ref.ordinal)
                cell.disclosure.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: item.isDirectory ? L10n.text("Abrir pasta") : nil)
                cell.disclosure.setAccessibilityLabel(expanded ? L10n.text("Recolher pasta") : L10n.text("Expandir pasta"))
                cell.disclosure.setAccessibilityValue(expanded ? 1 : 0)
                cell.disclosure.isHidden = !item.isDirectory || !model.search.isEmpty || model.showLargest
                cell.action = { [weak self] in self?.toggle(item, ref: ref) }
                cell.name.stringValue = model.explorerName(item); cell.icon.image = NSImage(systemSymbolName: item.isSymbolicLink ? "link" : item.isDirectory ? "folder.fill" : "doc", accessibilityDescription: nil)
                cell.icon.contentTintColor = item.isDirectory ? .systemBlue : .secondaryLabelColor
                cell.setAccessibilityLabel(model.explorerName(item) + ", " + model.sizeText(item, allocated: model.allocatedOrder))
                cell.name.toolTip = item.path; return cell
            }
            if column == "size" { return label(model.sizeText(item, allocated: model.allocatedOrder), identifier: column) }
            let denominator = model.allocatedOrder ? model.currentFolder?.allocatedBytes ?? 0 : model.currentFolder?.logicalBytes ?? 0
            let numerator = model.allocatedOrder ? item.allocatedBytes : item.logicalBytes
            return label(denominator > 0 && item.coverage == .complete ? String(format: "%.1f%%", Double(numerator)/Double(denominator)*100) : "—", identifier: column)
        }
        func label(_ value: String, identifier: String) -> NSTextField {
            let field = NSTextField(labelWithString: value); field.lineBreakMode = .byTruncatingMiddle
            field.font = .systemFont(ofSize: 12); field.alignment = identifier == "name" ? .left : .right
            field.setAccessibilityLabel(value); return field
        }
        func toggle(_ item: ScanItem, ref: VirtualTreeReference) {
            guard item.isDirectory, model.search.isEmpty, !model.showLargest else { return }
            if branch.isExpanded(parent: ref.parent, ordinal: ref.ordinal) {
                branch.setExpansion(parent: ref.parent, ordinal: ref.ordinal, branch: nil); reloadPreservingSelection()
            } else { request(parent: item.path, offset: 0, expand: (ref.parent, ref.ordinal)) }
        }
        private func reloadWithoutSelectionNotification() {
            let previous = synchronizingSelection; synchronizingSelection = true
            table?.reloadData(); synchronizingSelection = previous
        }
        func reloadPreservingSelection() {
            synchronizingSelection = true
            table?.reloadData()
            if let ref = selectedReference, let row = branch.rowIndex(parent: ref.parent, ordinal: ref.ordinal) {
                table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else { table?.deselectAll(nil) }
            synchronizingSelection = false
            synchronizeSelection()
        }
        func synchronizeSelection() {
            guard let row = table?.selectedRow, row >= 0, let ref = branch.reference(at: row) else {
                selectedReference = nil; model.clearExplorerSelection(); return
            }
            selectedReference = ref
            guard let (item, _) = item(at: row) else { model.clearExplorerSelection(); return }
            model.selectExplorerItem(item)
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizingSelection else { return }
            synchronizeSelection()
        }
        @objc func openSelection() {
            guard let row = table?.selectedRow, let (item, _) = item(at: row) else { return }
            model.openFolder(item)
        }
        func key(_ event: NSEvent) -> Bool {
            guard let row = table?.selectedRow, row >= 0, let (item, ref) = item(at: row) else { return false }
            switch event.keyCode {
            case 124: if item.isDirectory { if !branch.isExpanded(parent: ref.parent, ordinal: ref.ordinal) { toggle(item, ref: ref) }; return true }
            case 123:
                if branch.isExpanded(parent: ref.parent, ordinal: ref.ordinal) { toggle(item, ref: ref) }
                else if let parent = branch.parentReference(of: ref.parent), let row = branch.rowIndex(parent: parent.parent, ordinal: parent.ordinal) { table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table?.scrollRowToVisible(row) }
                else { model.goBack() }
                return true
            case 36: openSelection(); return true
            case 51, 117: reviewTrash(); return true
            default: break
            }
            return false
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let row = table?.clickedRow, row >= 0, let (item, _) = item(at: row) else { return }
            model.selectExplorerItem(item); table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            for (title, action, allowed) in [(L10n.text("Abrir pasta"), #selector(openSelection), item.isDirectory), (L10n.text("Mostrar no Finder"), #selector(reveal), true), (L10n.text("Revisar envio à Lixeira…"), #selector(reviewTrash), model.trashPolicyReason(item) == nil && !model.busy && !model.isScanning)] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; entry.isEnabled = allowed; menu.addItem(entry)
            }
        }
        @objc func reveal() { if let item = model.selectedItem { model.showInFinder(item) } }
        @objc func reviewTrash() {
            guard let item = model.selectedItem, model.trashPolicyReason(item) == nil, !model.busy, !model.isScanning else { return }
            model.reviewTrash(item)
        }
    }
}

private final class TreeNameCell: NSTableCellView {
    let disclosure = NSButton(), icon = NSImageView(), name = NSTextField(labelWithString: "")
    var action: (() -> Void)?
    var leading: NSLayoutConstraint!
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        disclosure.isBordered = false; disclosure.imagePosition = .imageOnly; disclosure.target = self; disclosure.action = #selector(expand)
        name.lineBreakMode = .byTruncatingMiddle; name.font = .systemFont(ofSize: 13)
        for child in [disclosure, icon, name] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        leading = disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        NSLayoutConstraint.activate([leading, disclosure.widthAnchor.constraint(equalToConstant: 16), disclosure.centerYAnchor.constraint(equalTo: centerYAnchor), icon.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 4), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16), icon.centerYAnchor.constraint(equalTo: centerYAnchor), name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), name.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func expand() { action?() }
}

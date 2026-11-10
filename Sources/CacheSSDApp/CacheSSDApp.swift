import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mayTerminate: () -> Bool = { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { mayTerminate() ? .terminateNow : .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
}

@main struct CacheSSDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("DiskWing", id: "main") {
            ContentView().environmentObject(model).environment(\.locale, L10n.locale).frame(minWidth: 1050, minHeight: 690).tint(Palette.accent).onAppear { delegate.mayTerminate = { model.operationMessage == nil && !model.isScanning } }
        }
        .defaultSize(width: 1240, height: 810)
        .commands {
            CommandGroup(replacing: .newItem) { Button(L10n.text("Analisar pasta…")) { model.chooseFolder() }.keyboardShortcut("o") }
            CommandGroup(after: .toolbar) { Button(L10n.text("Atualizar análise")) { if let root = model.report?.root.url { model.scan(root) } }.keyboardShortcut("r").disabled(model.isScanning || model.busy) }
            CommandMenu(L10n.text("Navegar")) {
                Button(L10n.text("Visão geral")) { model.section = .overview }.keyboardShortcut("1")
                Button(L10n.text("Explorar espaço")) { model.section = .explorer }.keyboardShortcut("2")
                Button(L10n.text("Caches e SSD")) { model.section = .caches }.keyboardShortcut("3")
                Button(L10n.text("Histórico")) { model.section = .history }.keyboardShortcut("4")
                Button(L10n.text("Ajustes")) { model.section = .preferences }.keyboardShortcut("5")
            }
        }
        MenuBarExtra("DiskWing", systemImage: "externaldrive") {
            MenuContent().environmentObject(model)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.selectedVolume.map { L10n.text("\($0.name): \(CacheSSDCore.ByteText.format($0.freeBytes)) livres") } ?? L10n.text("SSD selecionado desconectado"))
        Button(L10n.text("Abrir DiskWing")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(L10n.text("Analisar pasta…")) { openWindow(id: "main"); model.chooseFolder() }
        Divider()
        Button(L10n.text("Usar somente o Mac")) { model.setLocalOnly() }.disabled(model.busy)
        if let volume = model.selectedVolume { Button(L10n.text("Preparar para ejetar \(volume.name)…")) { openWindow(id: "main"); model.review = .eject(volume) }.disabled(model.busy || model.isScanning) }
        Divider()
        Button(L10n.text("Encerrar DiskWing")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}

import CacheSSDCore

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
}

@main struct CacheSSDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("DiskWing", id: "main") {
            ContentView().environmentObject(model).environment(\.locale, Locale(identifier: "pt_BR")).frame(minWidth: 1050, minHeight: 690).tint(Palette.accent)
        }
        .defaultSize(width: 1240, height: 810)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Analisar pasta…") { model.chooseFolder() }.keyboardShortcut("o") }
            CommandGroup(after: .toolbar) { Button("Atualizar análise") { if let root = model.report?.root.url { model.scan(root) } }.keyboardShortcut("r").disabled(model.isScanning || model.busy) }
            CommandMenu("Navegar") {
                Button("Visão geral") { model.section = .overview }.keyboardShortcut("1")
                Button("Explorar espaço") { model.section = .explorer }.keyboardShortcut("2")
                Button("Caches e SSD") { model.section = .caches }.keyboardShortcut("3")
                Button("Histórico") { model.section = .history }.keyboardShortcut("4")
                Button("Ajustes") { model.section = .preferences }.keyboardShortcut("5")
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
        Text(model.selectedVolume.map { "\($0.name): \(CacheSSDCore.ByteText.format($0.freeBytes)) livres" } ?? "SSD selecionado desconectado")
        Button("Abrir DiskWing") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Analisar pasta…") { openWindow(id: "main"); model.chooseFolder() }
        Divider()
        Button("Usar somente o Mac") { model.setLocalOnly() }.disabled(model.busy)
        if let volume = model.selectedVolume { Button("Preparar para ejetar \(volume.name)…") { openWindow(id: "main"); model.review = .eject(volume) }.disabled(model.busy || model.isScanning) }
        Divider()
        Button("Encerrar DiskWing") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}

import CacheSSDCore

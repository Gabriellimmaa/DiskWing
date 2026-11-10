import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mayTerminate: () -> Bool = { true }
    var onFinishedLaunching: (() -> Void)?
    private(set) var hasFinishedLaunching = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { mayTerminate() ? .terminateNow : .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        onFinishedLaunching?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct CacheSSDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launch = LaunchCoordinator()
    var body: some Scene {
        WindowGroup("DiskWing", id: "main") {
            Group {
                if let model = launch.model { ContentView().environmentObject(model) }
                else { LaunchView(launch: launch) }
            }
            .environment(\.locale, L10n.locale).frame(minWidth: 1050, minHeight: 690).tint(Palette.accent)
            .onAppear {
                delegate.mayTerminate = { launch.model.map { $0.operationMessage == nil && !$0.isScanning } ?? true }
                delegate.onFinishedLaunching = { launch.start() }
                if delegate.hasFinishedLaunching { launch.start() }
            }
        }
        .defaultSize(width: 1240, height: 810)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Analisar pasta…")) { launch.model?.chooseFolder() }.keyboardShortcut("o").disabled(launch.model.map { $0.busy || $0.isScanning } ?? true)
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.text("Atualizar análise")) { if let model = launch.model, let root = model.report?.root.url { model.scan(root) } }.keyboardShortcut("r").disabled(launch.model.map { $0.isScanning || $0.busy } ?? true)
            }
            CommandMenu(L10n.text("Navegar")) {
                if let model = launch.model {
                    Button(L10n.text("Visão geral")) { model.section = .overview }.keyboardShortcut("1")
                    Button(L10n.text("Explorar espaço")) { model.section = .explorer }.keyboardShortcut("2")
                    Button(L10n.text("Caches e SSD")) { model.section = .caches }.keyboardShortcut("3")
                    Button(L10n.text("Histórico")) { model.section = .history }.keyboardShortcut("4")
                    Button(L10n.text("Ajustes")) { model.section = .preferences }.keyboardShortcut("5")
                }
            }
        }
        MenuBarExtra("DiskWing", systemImage: "externaldrive") {
            if let model = launch.model { MenuContent().environmentObject(model) }
            else {
                Text(L10n.text("Iniciando o DiskWing…"))
                Button(L10n.text("Encerrar DiskWing")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
    }
}

struct LaunchView: View {
    @ObservedObject var launch: LaunchCoordinator
    var body: some View {
        VStack(spacing: 16) {
            if let failure = launch.failureMessage {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).accessibilityHidden(true)
                Text(L10n.text("Não foi possível iniciar o DiskWing")).font(.title2)
                Text(failure).multilineTextAlignment(.center).frame(maxWidth: 480)
                Button(L10n.text("Tentar novamente")) { launch.start() }.accessibilityIdentifier("launch.retry")
            } else {
                ProgressView(L10n.text("Iniciando o DiskWing…")).accessibilityIdentifier("launch.progress")
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("launch.status")
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

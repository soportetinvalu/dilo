import AppKit
import Combine
import SwiftUI

/// Barra de menú, ventana de Ajustes y conexión de todas las piezas.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let transcriber = ParakeetTranscriber()
    private lazy var polisher = TextPolisher(settings: settings)
    private let hotkeys = HotkeyManager.shared
    private lazy var controller = DictationController(
        settings: settings, transcriber: transcriber, polisher: polisher, hotkeys: hotkeys
    )

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private lazy var comparisonWindow = DictationComparisonWindow(comparison: controller.comparison)
    private var cancellables = Set<AnyCancellable>()

    // MARK: Arranque

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Escribir en la tubería de un proceso que ya terminó (codex) no debe matar la app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        controller.start()

        // Si el usuario cambia la tecla en Ajustes, se aplica al instante.
        settings.$hotkey
            .sink { [weak self] binding in self?.hotkeys.binding = binding }
            .store(in: &cancellables)

        // El icono de la barra de menú refleja el estado.
        Publishers.CombineLatest3(controller.$state, transcriber.$state, hotkeys.$isActive)
            .sink { [weak self] state, model, hotkeyActive in
                self?.updateIcon(state: state, model: model, hotkeyActive: hotkeyActive)
            }
            .store(in: &cancellables)

        // Primera vez: abrir Ajustes (ahí están los permisos) y pedir el micrófono.
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            openSettings()
            Task { _ = await Permissions.requestMicrophone() }
        }
    }

    // MARK: Barra de menú

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self // el contenido se reconstruye cada vez que se abre
        statusItem.menu = menu
        updateIcon(state: .idle, model: .notLoaded, hotkeyActive: false)
    }

    private func updateIcon(state: DictationState, model: ModelState, hotkeyActive: Bool) {
        var symbol = "mic"
        var color: NSColor?
        switch state {
        case .recording:
            symbol = "mic.fill"
            color = .systemRed
        case .transcribing:
            symbol = "waveform"
        case .polishing:
            symbol = "sparkles"
        case .idle:
            if case .failed = model {
                symbol = "exclamationmark.triangle"
            } else if !hotkeyActive {
                symbol = "mic.slash"
            } else if model != .ready {
                symbol = "arrow.down.circle"
            }
        }

        guard let button = statusItem.button,
              var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dilo")
        else { return }
        if let color,
           let tinted = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) {
            image = tinted
            image.isTemplate = false
        } else {
            image.isTemplate = true
        }
        button.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine()))
        menu.addItem(disabledItem("Modelo de voz: \(transcriber.state.description)"))
        menu.addItem(.separator())

        let polishItem = NSMenuItem(title: "Pulir con ChatGPT", action: #selector(togglePolish), keyEquivalent: "")
        polishItem.target = self
        polishItem.state = settings.polishEnabled ? .on : .off
        menu.addItem(polishItem)
        if settings.polishEnabled && polisher.status != .ready {
            menu.addItem(disabledItem("codex: \(polisher.status.summary)"))
        }

        if !hotkeys.isActive {
            let item = NSMenuItem(title: "⚠︎ Faltan permisos: abrir Ajustes…", action: #selector(openSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if let notice = controller.lastNotice {
            menu.addItem(disabledItem(String(notice.prefix(90))))
        }

        let compare = NSMenuItem(title: "Ver último antes y después…", action: #selector(showComparison), keyEquivalent: "")
        compare.target = self
        compare.isEnabled = controller.state == .idle && controller.comparison.snapshot != nil
        // NSMenu auto-valida acciones: sin resultado tampoco debe poder habilitarla.
        if !compare.isEnabled { compare.action = nil }
        menu.addItem(compare)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let recheck = NSMenuItem(title: "Comprobar codex de nuevo", action: #selector(recheckCodex), keyEquivalent: "")
        recheck.target = self
        menu.addItem(recheck)
        let quit = NSMenuItem(title: "Salir de Dilo", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine() -> String {
        switch controller.state {
        case .recording: return "● Grabando…"
        case .transcribing: return "Transcribiendo…"
        case .polishing: return "Puliendo con ChatGPT…"
        case .idle:
            guard transcriber.state == .ready else { return "Preparando el modelo de voz…" }
            let key = settings.hotkey.displayName
            switch settings.mode {
            case .hold: return "Listo — mantén \(key) para dictar"
            case .toggle: return "Listo — pulsa \(key) para empezar y otra vez para terminar"
            }
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Acciones

    @objc private func showComparison() {
        guard controller.state == .idle else { return }
        comparisonWindow.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.comparison.clear()
    }

    @objc private func togglePolish() {
        settings.polishEnabled.toggle()
        if settings.polishEnabled { Task { await polisher.refreshStatus() } }
    }

    @objc private func recheckCodex() {
        Task { await polisher.refreshStatus() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, transcriber: transcriber, polisher: polisher, hotkeys: hotkeys)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Dilo — Ajustes"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

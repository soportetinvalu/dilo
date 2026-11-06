import AppKit
import Combine
import SwiftUI

/// Solo se abre desde una acción explícita del menú. Nunca activa la app al capturar.
@MainActor
final class DictationComparisonWindow: NSObject, NSWindowDelegate {
    private let comparison: LastDictationComparison
    private(set) var window: NSWindow?
    private var subscription: AnyCancellable?

    init(comparison: LastDictationComparison) {
        self.comparison = comparison
        super.init()
        subscription = comparison.$snapshot.sink { [weak self] snapshot in
            // El siguiente intento de dictado elimina también cualquier vista abierta.
            if snapshot == nil { self?.window?.close() }
        }
    }

    func show() {
        guard let snapshot = comparison.snapshot else { return }
        if window == nil {
            let view = DictationComparisonView(snapshot: snapshot)
            let panel = NSWindow(contentViewController: NSHostingController(rootView: view))
            panel.title = "Dilo — Último antes y después"
            panel.styleMask = [.titled, .closable, .resizable]
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.contentMinSize = NSSize(width: 520, height: 420)
            panel.setContentSize(NSSize(width: 660, height: 580))
            panel.delegate = self
            panel.center()
            window = panel
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Soltar también el HostingController: no basta con ocultar la ventana.
        window?.contentViewController = nil
        window = nil
        comparison.clear()
    }
}

struct DictationComparisonView: View {
    let snapshot: LastDictationComparison.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Último dictado: antes y después").font(.headline)
            Text("Solo en memoria. Se borra al cerrar esta ventana, al iniciar otro dictado o al salir de Dilo. No se guarda un historial ni se vuelve a enviar el texto.")
                .font(.callout)
            Text(snapshot.step.summary).font(.callout).bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Antes de ChatGPT (transcripción local)", text: snapshot.raw)
                    Divider()
                    section(snapshot.step.afterTitle, text: snapshot.finalText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            Text("Compara con lo que dijiste. Si el cambio ya está en «Antes», apareció antes del pulido; si solo está en «Después», apareció en el pulido. Esto no comprueba la precisión del reconocimiento ni el pegado en otra app.")
                .font(.callout)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            // Sin selección/copia automática ni controles que cambien el portapapeles.
            Text(verbatim: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

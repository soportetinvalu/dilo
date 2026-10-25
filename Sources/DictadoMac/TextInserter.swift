import AppKit
import ApplicationServices
import os

enum InsertResult {
    /// Se pegó en la app activa y se restauró el portapapeles.
    case pasted
    /// No hay permiso de Accesibilidad: el texto quedó en el portapapeles para pegarlo a mano (⌘V).
    case copiedOnly
}

/// Inserta texto en la app activa: portapapeles + ⌘V, y luego restaura el portapapeles anterior.
@MainActor
final class TextInserter {
    /// Cuánto se espera antes de restaurar el portapapeles (las apps lentas leen tarde).
    static let restoreDelay: UInt64 = 300_000_000 // 300 ms

    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Inserter")

    /// Copia de TODO el portapapeles: cada elemento con todos sus tipos (texto, imágenes, RTF, archivos…).
    private typealias Snapshot = [[(type: NSPasteboard.PasteboardType, data: Data)]]

    func insert(_ text: String) async -> InsertResult {
        let pasteboard = NSPasteboard.general

        // Sin Accesibilidad no se puede enviar ⌘V: se deja el texto copiado y se avisa.
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedOnly
        }

        let snapshot = takeSnapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Marca estándar para que los gestores de portapapeles no guarden este texto temporal.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChangeCount = pasteboard.changeCount

        sendCommandV()

        try? await Task.sleep(nanoseconds: Self.restoreDelay)

        // Si el usuario copió otra cosa mientras tanto, no se pisa su copia.
        if pasteboard.changeCount == ourChangeCount {
            restore(snapshot, to: pasteboard)
        } else {
            log.info("El portapapeles cambió durante el pegado; no se restaura")
        }
        return .pasted
    }

    // MARK: Portapapeles

    private func takeSnapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            }
        }
    }

    private func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    // MARK: ⌘V

    private func sendCommandV() {
        let vKey: CGKeyCode = 9 // tecla "V"
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        // Solo ⌘: así no se mezcla con una tecla modificadora que siga pulsada (p. ej. Option).
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

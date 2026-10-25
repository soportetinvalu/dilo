import AppKit
import SwiftUI

/// Graba una tecla o combinación pulsada por el usuario.
/// - Un modificador solo (p. ej. Option derecha): púlsalo y suéltalo sin tocar nada más.
/// - Una tecla con modificadores (p. ej. ⌃⌥Espacio) o una tecla de función (F5…).
/// - Esc cancela.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hint: String?

    private var monitor: Any?
    private var onCapture: ((HotkeyBinding) -> Void)?
    /// Modificador pulsado que podría ser el atajo si se suelta sin pulsar nada más.
    private var pendingModifier: UInt16?
    /// true mientras hay una combinación de varios modificadores en curso (no vale como atajo solo).
    private var chordInProgress = false

    func start(onCapture: @escaping (HotkeyBinding) -> Void) {
        stop()
        self.onCapture = onCapture
        isRecording = true
        hint = nil
        pendingModifier = nil
        chordInProgress = false
        // Mientras se graba, la tecla actual no debe disparar un dictado.
        HotkeyManager.shared.isSuspended = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Los monitores locales se ejecutan en el hilo principal.
            let swallowed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallowed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCapture = nil
        pendingModifier = nil
        if isRecording { HotkeyManager.shared.isSuspended = false }
        isRecording = false
    }

    /// Devuelve true si el evento se consume (para que no suene el "bonk" del sistema).
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = UInt64(event.modifierFlags.rawValue)

        switch event.type {
        case .keyDown:
            let code = event.keyCode
            let flags = modifiers & ModifierMask.all
            if code == 53 && flags == 0 { // Esc
                stop()
                return true
            }
            if flags == 0 && !HotkeyBinding.isAllowedWithoutModifiers(code) {
                hint = "Esa tecla escribe texto: combínala con ⌘, ⌥, ⌃ o ⇧, o elige una tecla F."
                return true
            }
            finish(HotkeyBinding(kind: .key, keyCode: code, modifiers: flags))
            return true

        case .flagsChanged:
            let code = event.keyCode
            guard let deviceMask = HotkeyBinding.deviceMask(forModifierKeyCode: code) else { return true }
            let pressed = modifiers & deviceMask != 0
            if pressed {
                if pendingModifier == nil && !chordInProgress {
                    pendingModifier = code
                } else {
                    pendingModifier = nil
                    chordInProgress = true
                }
            } else {
                if pendingModifier == code {
                    finish(HotkeyBinding(kind: .modifierKey, keyCode: code))
                } else if modifiers & ModifierMask.all == 0 {
                    chordInProgress = false
                    pendingModifier = nil
                }
            }
            return true

        default:
            return false
        }
    }

    private func finish(_ binding: HotkeyBinding) {
        let callback = onCapture
        stop()
        callback?(binding)
    }
}

/// Fila de Ajustes: muestra la tecla actual y permite cambiarla.
struct ShortcutRecorderView: View {
    @Binding var binding: HotkeyBinding
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recorder.isRecording ? "Pulsa la tecla o combinación…" : binding.displayName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(recorder.isRecording ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15))
                    )
                Spacer()
                if recorder.isRecording {
                    Button("Cancelar") { recorder.stop() }
                } else {
                    Button("Cambiar…") { recorder.start { binding = $0 } }
                    Button("Restablecer") { binding = .default }
                        .disabled(binding == .default)
                }
            }
            if let hint = recorder.hint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { recorder.stop() }
    }
}

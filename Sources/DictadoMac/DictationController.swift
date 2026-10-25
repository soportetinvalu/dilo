import AppKit
import Foundation
import os

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case polishing
}

/// Orquesta un dictado completo: tecla → grabar → transcribir → (pulir) → insertar.
@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    /// Último aviso útil para mostrar en el menú (p. ej. "se insertó sin pulir porque…").
    @Published private(set) var lastNotice: String?

    let settings: AppSettings
    let transcriber: ParakeetTranscriber
    let polisher: TextPolisher
    let hotkeys: HotkeyManager

    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private let overlay = OverlayController()
    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Dictation")

    /// Grabaciones más cortas que esto (segundos) se descartan: suelen ser pulsaciones accidentales.
    private let minimumSeconds = 0.4

    init(settings: AppSettings, transcriber: ParakeetTranscriber, polisher: TextPolisher, hotkeys: HotkeyManager) {
        self.settings = settings
        self.transcriber = transcriber
        self.polisher = polisher
        self.hotkeys = hotkeys
    }

    // MARK: Arranque

    func start() {
        hotkeys.binding = settings.hotkey
        hotkeys.onPress = { [weak self] in self?.handlePress() }
        hotkeys.onRelease = { [weak self] in self?.handleRelease() }
        hotkeys.onInterrupt = { [weak self] in self?.handleInterrupt() }
        hotkeys.start()

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.updateLevel(level) }
        }
        recorder.onLimitReached = { [weak self] in
            Task { @MainActor in self?.finishRecording() }
        }

        // El modelo se carga al arrancar para que el primer dictado sea rápido.
        Task { await transcriber.prepare() }
        Task { await polisher.refreshStatus() }
    }

    // MARK: Eventos de la tecla

    private func handlePress() {
        switch settings.mode {
        case .hold:
            if state == .idle { beginRecording() }
        case .toggle:
            if state == .idle {
                beginRecording()
            } else if state == .recording {
                finishRecording()
            }
        }
    }

    private func handleRelease() {
        if settings.mode == .hold, state == .recording {
            finishRecording()
        }
    }

    /// Se pulsó otra tecla junto al modificador: no era un dictado.
    private func handleInterrupt() {
        guard state == .recording else { return }
        _ = recorder.stop()
        state = .idle
        overlay.hide()
        log.info("Grabación descartada: se usó la tecla como parte de otro atajo")
    }

    // MARK: Grabar

    private func beginRecording() {
        guard transcriber.state == .ready else {
            overlay.show(.message("El modelo de voz aún no está listo (\(transcriber.state.description))"), autoHideAfter: 3)
            return
        }
        switch Permissions.microphoneStatus {
        case .authorized:
            break
        case .notDetermined:
            Task {
                let granted = await Permissions.requestMicrophone()
                overlay.show(.message(granted ? "Micrófono permitido. Vuelve a pulsar la tecla." : "Sin permiso de micrófono"), autoHideAfter: 3)
            }
            return
        default:
            overlay.show(.message("Falta el permiso de micrófono (Ajustes del Sistema → Privacidad)"), autoHideAfter: 4)
            return
        }

        do {
            let deviceID = settings.microphoneUID.isEmpty ? nil : AudioDevices.device(withUID: settings.microphoneUID)?.id
            try recorder.start(deviceID: deviceID)
            state = .recording
            lastNotice = nil
            overlay.show(.recording)
            playSound("Tink")
        } catch {
            log.error("No se pudo empezar a grabar: \(error.localizedDescription, privacy: .public)")
            overlay.show(.message("No se pudo grabar: \(error.localizedDescription)"), autoHideAfter: 4)
        }
    }

    private func finishRecording() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        playSound("Pop")

        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        guard seconds >= minimumSeconds else {
            state = .idle
            overlay.hide()
            return
        }
        state = .transcribing
        overlay.show(.transcribing)
        Task { await process(samples) }
    }

    // MARK: Transcribir → pulir → insertar

    private func process(_ samples: [Float]) async {
        defer { state = .idle }
        do {
            let raw = try await transcriber.transcribe(samples)
            guard !raw.isEmpty else {
                overlay.show(.message("No se entendió nada"), autoHideAfter: 2)
                return
            }

            var finalText = raw
            var polishNotice: String?
            if settings.polishEnabled {
                state = .polishing
                overlay.show(.polishing)
                switch await polisher.polish(raw) {
                case .polished(let text):
                    finalText = text
                case .fallback(let reason):
                    polishNotice = "Se insertó el texto sin pulir: \(reason)"
                    log.notice("Pulido omitido: \(reason, privacy: .public)")
                }
            }
            lastNotice = polishNotice

            overlay.hide()
            switch await inserter.insert(finalText) {
            case .pasted:
                if let polishNotice { overlay.show(.message(polishNotice), autoHideAfter: 3) }
            case .copiedOnly:
                overlay.show(.message("Texto copiado al portapapeles (pega con ⌘V). Falta el permiso de Accesibilidad."), autoHideAfter: 5)
            }
        } catch {
            log.error("Fallo al transcribir: \(error.localizedDescription, privacy: .public)")
            overlay.show(.message("Error al transcribir: \(error.localizedDescription)"), autoHideAfter: 4)
        }
    }

    private func playSound(_ name: String) {
        guard settings.soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

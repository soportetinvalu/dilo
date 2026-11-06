// Controlador y ventana de producción; solo audio, ASR, pulido y pegado son dobles.
// No micrófono, TCC, red, login, dictados privados ni escritura de textos.
import AppKit
import Combine
import Foundation

@MainActor final class AppSettings {
    enum Mode { case hold, toggle }
    var mode = Mode.hold
    var hotkey = 0
    var microphoneUID = ""
    var soundsEnabled = false
    var polishEnabled = true
}
@MainActor final class ParakeetTranscriber {
    enum State: Equatable { case ready, notLoaded; var description: String { "synthetic" } }
    var state = State.ready
    var raw = "SYNTHETIC-BEFORE-731"
    var fails = false
    var calls = 0
    func prepare() async {}
    func transcribe(_ samples: [Float]) async throws -> String {
        calls += 1
        if fails { throw NSError(domain: "synthetic", code: 1) }
        return raw
    }
}
enum PolishOutcome { case polished(String), fallback(reason: String) }
@MainActor final class TextPolisher {
    var outcome = PolishOutcome.polished("SYNTHETIC-AFTER-947")
    var calls = 0
    var received: [String] = []
    func refreshStatus() async {}
    func polish(_ raw: String) async -> PolishOutcome { calls += 1; received.append(raw); return outcome }
}
@MainActor final class HotkeyManager {
    var binding = 0
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onInterrupt: (() -> Void)?
    func start() {}
}
@MainActor final class AudioRecorder {
    static let sampleRate = 16000.0
    static var sampleCount = 8000
    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    func start(deviceID: Int?) throws {}
    func stop() -> [Float] { [Float](repeating: 0, count: Self.sampleCount) }
}
@MainActor enum AudioDevices {
    struct Device { let id: Int }
    static func device(withUID: String) -> Device? { nil }
}
@MainActor enum Permissions {
    enum Status { case authorized, notDetermined, denied }
    static var microphoneStatus = Status.authorized
    static var requests = 0
    static func requestMicrophone() async -> Bool { requests += 1; return false }
}
enum InsertResult { case pasted, copiedOnly }
@MainActor final class TextInserter {
    static var result = InsertResult.pasted
    static var texts: [String] = []
    static var duringInsert: (() -> Void)?
    func insert(_ text: String) async -> InsertResult {
        Self.duringInsert?()
        await Task.yield()
        Self.texts.append(text)
        return Self.result
    }
}
@MainActor final class OverlayController {
    enum Content { case recording, transcribing, polishing, message(String) }
    func updateLevel(_ level: Float) {}
    func show(_ content: Content, autoHideAfter: Double = 0) {}
    func hide() {}
}

@main struct DictationComparisonTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "ok" : "FALLA") \(label)")
        }
        let settings = AppSettings()
        let transcriber = ParakeetTranscriber()
        let polisher = TextPolisher()
        let hotkeys = HotkeyManager()
        let controller = DictationController(settings: settings, transcriber: transcriber, polisher: polisher, hotkeys: hotkeys)
        controller.start()
        let store = controller.comparison
        let viewer = DictationComparisonWindow(comparison: store)
        let clipboardCount = NSPasteboard.general.changeCount
        let permissionRequests = Permissions.requests
        let defaultsDomain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let preferences = (UserDefaults.standard.persistentDomain(forName: defaultsDomain) ?? [:]) as NSDictionary
        check(store.snapshot == nil, "inicio sin dictados retenidos")
        viewer.show()
        check(viewer.window == nil, "sin resultado no se abre una ventana")
        TextInserter.duringInsert = {
            check(store.snapshot == nil && viewer.window == nil, "no publica ni abre diagnóstico durante el pegado")
        }
        func dictate() async {
            hotkeys.onPress?()
            hotkeys.onRelease?()
            for _ in 0..<500 {
                if controller.state == .idle { return }
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            check(false, "dictado termina dentro del plazo sintético")
        }
        await dictate()
        check(store.snapshot == .init(raw: transcriber.raw, finalText: "SYNTHETIC-AFTER-947", step: .completed), "conserva antes y después distintos de la misma ejecución")
        check(transcriber.calls == 1 && polisher.calls == 1 && polisher.received == [transcriber.raw], "una transcripción y un pulido, con el raw exacto")
        check(TextInserter.texts == ["SYNTHETIC-AFTER-947"], "inserta solo la salida final una vez")
        check(viewer.window == nil, "capturar no revela texto ni abre ventana")
        viewer.show()
        weak var releasedPanel = viewer.window
        check(viewer.window?.isVisible == true && viewer.window?.isRestorable == false, "acción explícita abre ventana nativa sin restauración")
        viewer.window?.close()
        check(store.snapshot == nil && viewer.window == nil && releasedPanel?.contentViewController == nil, "cerrar borra el resultado y libera la ventana y su vista")
        viewer.show()
        check(viewer.window == nil, "cerrar no permite volver a revelar el dictado borrado")

        polisher.outcome = .polished(transcriber.raw)
        await dictate()
        check(store.snapshot?.step == .completed && store.snapshot?.raw == store.snapshot?.finalText,
              "respuesta idéntica sigue siendo pulido completado")
        store.clear()

        // Pulido apagado no se confunde con una respuesta de ChatGPT.
        settings.polishEnabled = false
        transcriber.raw = "SYNTHETIC-SECOND-583"
        await dictate()
        check(store.snapshot == .init(raw: transcriber.raw, finalText: transcriber.raw, step: .disabled) && polisher.calls == 2, "apagado conserva raw sin invocar pulidor")
        viewer.show()
        hotkeys.onPress?()
        check(store.snapshot == nil && viewer.window == nil, "siguiente inicio borra también la vista abierta antes de grabar")
        hotkeys.onInterrupt?()
        check(controller.state == .idle && store.snapshot == nil, "atajo interrumpido no recupera el resultado anterior")

        settings.polishEnabled = true
        polisher.outcome = .fallback(reason: "synthetic failure")
        TextInserter.result = .copiedOnly
        await dictate()
        check(store.snapshot?.step == .fallback && store.snapshot?.finalText == transcriber.raw, "fallback etiquetado sin atribuir respuesta a ChatGPT")
        check(TextInserter.texts.last == transcriber.raw, "copiado sin accesibilidad conserva el mismo texto usado")
        check(store.snapshot?.step.afterTitle == "Texto usado (sin pulir)", "fallback no presenta un después de ChatGPT ficticio")

        // Se borra incluso si el siguiente intento falla antes de grabar.
        transcriber.state = .notLoaded
        hotkeys.onPress?()
        check(store.snapshot == nil, "modelo no listo no deja visible un dictado ajeno anterior")
        transcriber.state = .ready
        await dictate()
        Permissions.microphoneStatus = .denied
        hotkeys.onPress?()
        check(store.snapshot == nil, "permiso denegado no conserva el resultado anterior")
        Permissions.microphoneStatus = .authorized
        await dictate()
        AudioRecorder.sampleCount = 1
        await dictate()
        check(store.snapshot == nil, "grabación corta no conserva ni fabrica un resultado")
        AudioRecorder.sampleCount = 8000
        await dictate()
        transcriber.raw = ""
        await dictate()
        check(store.snapshot == nil, "transcripción vacía no revela un dictado anterior")
        transcriber.raw = "SYNTHETIC-THIRD-269"
        await dictate()
        transcriber.fails = true
        await dictate()
        check(store.snapshot == nil, "error ASR no conserva el dictado anterior")
        store.capture(raw: "", finalText: "synthetic", step: .completed)
        check(store.snapshot == nil, "almacén rechaza un raw vacío")
        store.capture(raw: " A\nB ", finalText: " C\nD ", step: .completed)
        check(store.snapshot?.raw == " A\nB " && store.snapshot?.finalText == " C\nD ", "comparación no normaliza ni altera los textos")
        store.clear()
        check(NSPasteboard.general.changeCount == clipboardCount, "diagnóstico no escribe en el portapapeles real")
        check(Permissions.requests == permissionRequests, "diagnóstico no solicita permisos")
        check(preferences.isEqual((UserDefaults.standard.persistentDomain(forName: defaultsDomain) ?? [:]) as NSDictionary), "diagnóstico no añade preferencias persistidas")
        print("Comparación: \(checks) comprobaciones, \(failures) fallos; dependencias sintéticas, ventana nativa.")
        exit(failures == 0 ? 0 : 1)
    }
}

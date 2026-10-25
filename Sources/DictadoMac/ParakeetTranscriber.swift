import FluidAudio
import Foundation
import os

/// Estado del modelo de voz, para mostrarlo en el menú y en Ajustes.
enum ModelState: Equatable {
    case notLoaded
    case downloading(Double)   // 0...1
    case compiling             // Core ML prepara el modelo (la primera vez tarda)
    case loading
    case ready
    case failed(String)

    var description: String {
        switch self {
        case .notLoaded: return "sin cargar"
        case .downloading(let p): return "descargando \(Int(p * 100)) %"
        case .compiling: return "preparando para este Mac (solo la primera vez)…"
        case .loading: return "cargando…"
        case .ready: return "listo"
        case .failed(let reason): return "error: \(reason)"
        }
    }
}

enum TranscriberError: LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady: return "El modelo de voz todavía no está listo."
        }
    }
}

/// Transcripción 100 % local con Parakeet TDT 0.6B v3 (FluidAudio / Core ML).
/// El audio nunca sale del Mac. Los modelos se descargan una vez de HuggingFace
/// a ~/Library/Application Support/FluidAudio/Models/.
@MainActor
final class ParakeetTranscriber: ObservableObject {
    @Published private(set) var state: ModelState = .notLoaded

    private var manager: AsrManager?
    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Transcriber")

    /// Descarga (si hace falta) y carga el modelo. Se llama al arrancar la app.
    func prepare() async {
        switch state {
        case .ready, .loading, .downloading, .compiling: return
        case .notLoaded, .failed: break
        }
        state = .downloading(0)
        do {
            // v3 = multilingüe (25 idiomas, incluido español, con puntuación y mayúsculas).
            let models = try await AsrModels.downloadAndLoad(
                version: .v3,
                progressHandler: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    var compiling = false
                    if case .compiling = progress.phase { compiling = true }
                    Task { @MainActor in
                        guard let self else { return }
                        // Si ya estamos en "listo" no se retrocede.
                        if self.state == .ready { return }
                        self.state = compiling ? .compiling : .downloading(fraction)
                    }
                }
            )
            state = .loading
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            manager = asr

            // Calentamiento: una transcripción de 1 s de silencio para que la primera real no pague el arranque.
            _ = try? await run(asr, samples: [Float](repeating: 0, count: 16_000))

            state = .ready
            log.info("Modelo Parakeet v3 listo")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("No se pudo cargar el modelo: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Transcribe muestras Float32 mono a 16 kHz. Devuelve el texto en español.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager, state == .ready else { throw TranscriberError.notReady }
        return try await run(manager, samples: samples)
    }

    private func run(_ asr: AsrManager, samples: [Float]) async throws -> String {
        // El estado del decodificador se crea nuevo en cada dictado (cada uno es independiente).
        var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(samples, decoderState: &decoderState, language: .spanish)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

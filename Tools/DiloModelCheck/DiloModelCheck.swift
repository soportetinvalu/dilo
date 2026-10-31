import FluidAudio
import Foundation

@main
struct DiloModelCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DiloModelCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Indica Dilo.app/Contents/Resources/ParakeetV3"])
        }
        // loadLocal no resuelve repositorios ni descarga. No usa micrófono ni TCC.
        let models = try AsrModels.loadLocal(
            from: URL(fileURLWithPath: CommandLine.arguments[1]), version: .v3)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(
            [Float](repeating: 0, count: 16_000), decoderState: &state, language: .spanish)
        guard result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "DiloModelCheck", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "El silencio generó texto inesperado"])
        }
        print("Core ML: carga local y transcripción de 1 s de silencio correctas (no prueba micrófono, TCC ni pegado).")
    }
}

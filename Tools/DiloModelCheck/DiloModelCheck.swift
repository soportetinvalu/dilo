import FluidAudio
import Foundation

@main
struct DiloModelCheck {
    struct Fixture: Decodable {
        let path: String
    }
    struct Manifest: Decodable {
        let samples: [Fixture]
    }
    struct Transcript: Encodable {
        let path: String
        let text: String
    }

    static func main() async throws {
        let args = CommandLine.arguments
        let speech = args.count == 7 && args[1] == "--public-fixtures"
        guard args.count == 2 || speech else {
            throw NSError(domain: "DiloModelCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Indica el modelo local o --public-fixtures modelo int8|int8V2 manifiesto salida confirm-public"])
        }
        if speech && (args[6] != "confirm-public" || !["int8", "int8V2"].contains(args[3])) {
            throw NSError(domain: "DiloModelCheck", code: 3)
        }
        // Solo la comparación explícita de fixtures públicas admite la variante anterior.
        // La app y el smoke normal restauran el encoder original de FluidAudio 0.17.7.
        let directory = speech ? args[2] : args[1]
        let models: AsrModels
        if speech && args[3] == "int8V2" {
            models = try AsrModels.loadLocal(
                from: URL(fileURLWithPath: directory), version: .v3,
                encoderPrecision: .int8V2)
        } else {
            models = try AsrModels.loadLocal(
                from: URL(fileURLWithPath: directory), version: .v3,
                encoderPrecision: .int8)
        }
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
        if speech {
            let manifestURL = URL(fileURLWithPath: args[4])
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            var transcripts: [Transcript] = []
            for fixture in manifest.samples {
                let samples = try AudioConverter().resampleAudioFile(
                    manifestURL.deletingLastPathComponent().appendingPathComponent(fixture.path))
                // Como la app: muestras mono a 16 kHz, español y estado nuevo por dictado.
                var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
                let output = try await asr.transcribe(samples, decoderState: &decoderState, language: .spanish)
                transcripts.append(Transcript(path: fixture.path, text: output.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(transcripts).write(to: URL(fileURLWithPath: args[5]), options: .atomic)
            print("Comparación: \(transcripts.count) fixtures públicas transcritas; sin pulido.")
        }
    }
}

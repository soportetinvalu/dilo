import CryptoKit
import FluidAudio
import Foundation

// Ruta privada separada de DiloModelCheck: no lee fixtures públicas ni acepta WAV en claro.
// Entrada: AES-256-GCM con clave temporal (variable DILO_PRIVADO_K_IN, base64).
// Salida: X25519 efímera + HKDF-SHA256 + AES-256-GCM hacia DILO_RETURN_PUBKEY.
// El audio y el texto solo existen en memoria; stdout nunca contiene datos de voz.
enum PrivateError: Error, CustomStringConvertible {
    case usage, key(String), format(String), wav(String)
    var description: String {
        switch self {
        case .usage: return "uso: transcribe <modelo> <run_id> <dir> <etiquetas...> | seal <etiqueta> <run_id> <archivo> <salida>"
        case .key(let what): return "clave inválida o ausente: " + what
        case .format(let what): return "formato cifrado inválido: " + what
        case .wav(let what): return "WAV no admitido: " + what
        }
    }
}

@main
struct DiloPrivateCheck {
    static let inMagic = Data("DILOIN01".utf8)
    static let outMagic = Data("DILOOUT1".utf8)
    static let outInfo = Data("dilo-private-output-v1".utf8)
    static let allowedLabels: Set<String> = ["ficticio", "real", "diag"]

    static func secret(_ name: String) throws -> Data {
        guard let value = ProcessInfo.processInfo.environment[name],
              let data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              data.count == 32 else { throw PrivateError.key(name) }
        unsetenv(name)
        return data
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func seal(_ plaintext: Data, label: String, runID: String,
                     recipient: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: ephemeralPublic + recipient.rawRepresentation,
            sharedInfo: outInfo, outputByteCount: 32)
        let aad = outMagic + ephemeralPublic + Data((label + "|" + runID).utf8)
        guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined else {
            throw PrivateError.format("sello")
        }
        return outMagic + ephemeralPublic + combined
    }

    static func open(_ data: Data, label: String, key: SymmetricKey) throws -> Data {
        let bytes = Data(data)
        guard bytes.count > 8 + 12 + 16, bytes.prefix(8) == inMagic else { throw PrivateError.format("entrada") }
        let box = try AES.GCM.SealedBox(combined: Data(bytes.dropFirst(8)))
        return try AES.GCM.open(box, using: key, authenticating: inMagic + Data(label.utf8))
    }

    /// PCM 16 bits, mono, 16 kHz: el mismo formato que la app entrega a FluidAudio tras convertir.
    static func parseWav(_ data: Data) throws -> [Float] {
        let b = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard b.count >= 12, Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WAVE".utf8) else {
            throw PrivateError.wav("cabecera")
        }
        var i = 12
        var formatOK = false
        var pcm: ArraySlice<UInt8>?
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<(i + 4)], as: UTF8.self)
            let size = u32(i + 4)
            let start = i + 8
            guard start + size <= b.count else { throw PrivateError.wav("bloque truncado") }
            if id == "fmt " {
                guard size >= 16, u16(start) == 1, u16(start + 2) == 1, u32(start + 4) == 16_000, u16(start + 14) == 16 else {
                    throw PrivateError.wav("se exige PCM16 mono 16 kHz")
                }
                formatOK = true
            } else if id == "data" {
                pcm = b[start..<(start + size)]
            }
            i = start + size + (size & 1)
        }
        guard formatOK, let pcm, !pcm.isEmpty, pcm.count % 2 == 0 else { throw PrivateError.wav("sin datos PCM") }
        var samples = [Float]()
        samples.reserveCapacity(pcm.count / 2)
        var j = pcm.startIndex
        while j < pcm.endIndex {
            let value = Int16(bitPattern: UInt16(pcm[j]) | UInt16(pcm[j + 1]) << 8)
            samples.append(Float(value) / 32_768)
            j += 2
        }
        return samples
    }

    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data(("ERROR: " + String(describing: error) + "\n").utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 6, let runNumber = UInt64(args[3]) else { throw PrivateError.usage }
        let runID = String(runNumber)
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: try secret("DILO_RETURN_PUBKEY"))

        if args[1] == "seal" && args.count == 6 {
            // Diagnóstico propio (registro del helper) devuelto cifrado, nunca impreso.
            let file = URL(fileURLWithPath: args[4])
            let sealed = try seal(try Data(contentsOf: file), label: args[2], runID: runID, recipient: recipient)
            try sealed.write(to: URL(fileURLWithPath: args[5]), options: .atomic)
            print("sello \(args[2]): OK")
            return
        }
        guard args[1] == "transcribe" else { throw PrivateError.usage }
        let labels = Array(args[5...])
        guard !labels.isEmpty, Set(labels).count == labels.count, labels.allSatisfy({ allowedLabels.contains($0) && $0 != "diag" }) else {
            throw PrivateError.usage
        }
        let key = SymmetricKey(data: try secret("DILO_PRIVADO_K_IN"))
        let work = URL(fileURLWithPath: args[4], isDirectory: true)

        // Descifrar todo antes de cargar el modelo: una clave o entrada errónea falla pronto.
        var inputs: [(String, Data)] = []
        for label in labels {
            let sealed = try Data(contentsOf: work.appendingPathComponent("entrada-\(label).enc"))
            inputs.append((label, try open(sealed, label: label, key: key)))
        }

        let loadStart = Date()
        let models = try AsrModels.loadLocal(
            from: URL(fileURLWithPath: args[2]), version: .v3, encoderPrecision: .int8)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        // Como la app: calentamiento con 1 s de silencio y estado nuevo por dictado.
        var warmState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let warm = try await asr.transcribe([Float](repeating: 0, count: 16_000), decoderState: &warmState, language: .spanish)
        let silenceEmpty = warm.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let loadSeconds = Date().timeIntervalSince(loadStart)

        for (label, plain) in inputs {
            let digest = hex(SHA256.hash(data: plain))
            let samples = try parseWav(plain)
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let start = Date()
            let output = try await asr.transcribe(samples, decoderState: &state, language: .spanish)
            let elapsed = Date().timeIntervalSince(start)
            let result: [String: Any] = [
                "format": "dilo-private-result-v1",
                "label": label,
                "run_id": runID,
                "input_sha256": digest,
                "frames": samples.count,
                "seconds": Double(samples.count) / 16_000,
                "encoder_precision": "int8",
                "fluidaudio": "0.17.7",
                "language": "spanish",
                "polish": false,
                "warmup_silence_text_empty": silenceEmpty,
                "load_seconds": loadSeconds,
                "transcribe_seconds": elapsed,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "input_kind": "archivo WAV descifrado en memoria; no es entrada de micrófono",
                "text": output.text.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            let sealed = try seal(json, label: label, runID: runID, recipient: recipient)
            try sealed.write(to: work.appendingPathComponent("salida-\(label).enc"), options: .atomic)
            print("ronda \(label): OK")
        }
    }
}

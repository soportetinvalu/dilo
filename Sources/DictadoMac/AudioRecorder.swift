import AVFoundation
import AudioToolbox
import Foundation

enum RecorderError: LocalizedError {
    case noInput
    case deviceSelection(OSStatus)
    case converter

    var errorDescription: String? {
        switch self {
        case .noInput: return "No hay ningún micrófono disponible."
        case .deviceSelection(let status): return "No se pudo seleccionar el micrófono (código \(status))."
        case .converter: return "No se pudo preparar la conversión de audio a 16 kHz."
        }
    }
}

/// Graba del micrófono con AVAudioEngine y deja las muestras en el formato que
/// espera Parakeet: Float32, mono, 16 kHz. Todo queda en memoria; no se escribe audio a disco.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// Tope de seguridad por si la tecla se queda "pegada": 2 minutos.
    static let maxSamples = Int(sampleRate) * 120

    /// Nivel de volumen 0...1 (se llama desde el hilo de audio).
    var onLevel: (@Sendable (Float) -> Void)?
    /// Se llama (una vez) cuando se alcanza el tiempo máximo.
    var onLimitReached: (@Sendable () -> Void)?

    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var limitNotified = false
    private(set) var isRecording = false

    /// Empieza a grabar. `deviceID == nil` usa el micrófono predeterminado del sistema.
    func start(deviceID: AudioDeviceID?) throws {
        guard !isRecording else { return }

        // Motor nuevo en cada grabación: evita arrastrar estado de un micrófono anterior.
        let engine = AVAudioEngine()
        let input = engine.inputNode

        if var id = deviceID, let unit = input.audioUnit {
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { throw RecorderError.deviceSelection(status) }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.converter
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        limitNotified = false
        lock.unlock()

        // El mismo convertidor se usa en todos los bloques (mantiene el estado del filtro de remuestreo).
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer, converter: converter, outputFormat: outputFormat)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        isRecording = true
    }

    /// Para de grabar y devuelve todas las muestras (16 kHz, mono, Float32).
    func stop() -> [Float] {
        guard isRecording, let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRecording = false

        lock.lock()
        let result = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return result
    }

    /// Se ejecuta en el hilo de audio: convierte a 16 kHz mono y acumula.
    private func process(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil,
              let channel = output.floatChannelData?[0],
              output.frameLength > 0
        else { return }

        let frames = Int(output.frameLength)
        let chunk = UnsafeBufferPointer(start: channel, count: frames)

        // Nivel RMS para el indicador visual.
        var sum: Float = 0
        for value in chunk { sum += value * value }
        let rms = (sum / Float(frames)).squareRoot()
        onLevel?(min(1, rms * 8))

        lock.lock()
        var notifyLimit = false
        if samples.count + frames <= Self.maxSamples {
            samples.append(contentsOf: chunk)
        } else if !limitNotified {
            limitNotified = true
            notifyLimit = true
        }
        lock.unlock()

        if notifyLimit { onLimitReached?() }
    }
}

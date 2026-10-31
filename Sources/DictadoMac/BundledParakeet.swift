import FluidAudio
import Foundation

extension AsrModels {
    /// El paquete de CI carga sus pesos locales sin descargar ni tocar la caché.
    /// La compilación de fuentes conserva la descarga original si no trae pesos.
    static func diloLoad(
        version: AsrModelVersion = .v3,
        progressHandler: ProgressHandler? = nil
    ) async throws -> AsrModels {
        if let resources = Bundle.main.resourceURL {
            let directory = resources.appendingPathComponent("ParakeetV3", isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                // Si el paquete está incompleto, falla localmente: no oculta el error
                // con una descarga ni necesita Internet para el dictado empaquetado.
                return try loadLocal(from: directory, version: version, encoderPrecision: .int8V2)
            }
        }
        return try await downloadAndLoad(version: version, progressHandler: progressHandler)
    }
}
